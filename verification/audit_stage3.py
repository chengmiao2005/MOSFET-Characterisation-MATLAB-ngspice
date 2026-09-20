#!/usr/bin/env python3
"""Independently audit returned Stage 3 outputs; does not execute MATLAB/ngspice.
Usage: python audit_stage3.py --run RUN_DIR --out OUT_DIR \
       [--original-stage3 ORIGINAL_ZIP] [--original-stage2b RESULT_ZIP]
Requires Python, numpy, scipy, Pillow. Uses centred ordinary least squares,
not MATLAB or the delivered Python reference. Never edits source data.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path
from zipfile import ZipFile
import numpy as np
from scipy.io import loadmat
from PIL import Image

def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()
def line_fit(x,y):
    dx=x-x.mean()
    slope=float(np.dot(dx,y-y.mean())/np.dot(dx,dx))
    return np.array([slope,float(y.mean()-slope*x.mean())])
def current(vg,vd,p):
    vth,beta,lam=p
    over=np.maximum(vg-vth,0.0)
    # Independent piecewise implementation of the educational channel model.
    tri=(over>0)&(vd<over)
    sat=(over>0)&~tri
    ans=np.zeros_like(vg,dtype=float)
    ans[tri]=beta*(over[tri]*vd[tri]-vd[tri]**2/2)*(1+lam*vd[tri])
    ans[sat]=0.5*beta*over[sat]**2*(1+lam*vd[sat])
    return ans

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--original-stage3',type=Path);ap.add_argument('--original-stage2b',type=Path)
    a=ap.parse_args();p=a.run.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    checks=[]
    def check(name,ok,detail=None):
        checks.append(dict(name=name,passed=bool(ok),detail=detail))
    def csv(name): return np.loadtxt(p/name,delimiter=',',skiprows=1,ndmin=2)
    def close(x,y,atol=2e-16,rtol=1e-13):
        return np.shape(x)==np.shape(y) and np.allclose(x,y,atol=atol,rtol=rtol)
    status=(p/'STATUS.txt').read_text();cfg=json.loads((p/'config.json').read_text())
    check('Returned status is complete; MATLAB version and reused SPICE origin recorded',
          'STAGE3_STATUS=PASS_SAME_MODEL_POSTPROCESSING' in status and 'SELF_CHECKS=13/13' in status
          and 'MATLAB=24.1.0.2537033 (R2024a)' in status and 'SPICE_EXECUTED_THIS_STAGE=NO_REUSED_USER_OUTPUTS' in status)
    manifest=json.loads((p/'input_snapshot/SHA256.json').read_text())
    hash_bad=[k for k,h in manifest.items() if sha(p/'input_snapshot'/k)!=h]
    snapshot_files={str(f.relative_to(p/'input_snapshot')) for f in (p/'input_snapshot').rglob('*') if f.is_file() and f.name!='SHA256.json'}
    check('All input-snapshot SHA-256 values match manifest',set(manifest)==snapshot_files and not hash_bad,{'files':len(manifest),'mismatches':hash_bad,'manifest_covers_all_input_files':set(manifest)==snapshot_files})
    if a.original_stage2b:
        bad=[]
        with ZipFile(a.original_stage2b) as z:
            for rel in manifest:
                oldrel=rel if rel.startswith('spice_case/') else rel.removeprefix('stage2_')
                names=[n for n in z.namelist() if n.endswith('/'+oldrel)]
                if len(names)!=1 or hashlib.sha256(z.read(names[0])).hexdigest()!=sha(p/'input_snapshot'/rel):bad.append(rel)
        check('Snapshot matches the earlier successful Stage 2B return, byte-for-byte',not bad,{'mismatches':bad})
    if a.original_stage3:
        with ZipFile(a.original_stage3) as z:
            name=next(n for n in z.namelist() if n.endswith('/RUN_STAGE3.m'))
            original=z.read(name).decode('utf8')
        executed=(p/'executed_source.m').read_text()
        normalized=lambda x:'\n'.join(ln.strip() for ln in x.splitlines())
        # Replace only occurrences inside the validated voltage-grid block.
        lines=original.splitlines()
        for j in range(50,59):lines[j]=re.sub(r'\bgrid\b','voltageGrid',lines[j]) if "'Wrong voltage grid" not in lines[j] else lines[j]
        expected='\n'.join(lines)
        check('Executed source differs only by grid-to-voltageGrid fix and indentation',normalized(expected)==normalized(executed))
    expected_cfg={'transfer_fit_V':[1.7,2.7],'output_fit_V':[1.6,3],'candidate_lambda_per_V':[0,0.02,0.05],
                  'absolute_current_tolerance_A':1e-10,'relative_current_tolerance':1e-6,'bias_key_scale':1e9}
    check('Fit windows, candidates, grouping and original comparison tolerances unchanged',all(cfg[k]==v for k,v in expected_cfg.items()))
    names=['transfer_spice.dat']+[f'output_gate_{j}_spice.dat' for j in range(1,7)]+['low_vds_spice.dat']
    raw=[np.loadtxt(p/'input_snapshot/spice_case'/name,skiprows=1) for name in names]
    grid_ok=True
    for j,r in enumerate(raw):
        n=176 if j in (0,7) else 121
        grid_ok &= r.shape==(n,4) and np.isfinite(r).all()
        sweep=np.arange(n)*(0.02 if j in (0,7) else 0.025)
        grid_ok &= np.max(np.abs(r[:,0]-sweep))<1e-8
        if j in (0,7):grid_ok &= np.max(abs(r[:,1]-sweep))<1e-8 and np.max(abs(r[:,2]-(3 if j==0 else 0.2)))<1e-8
        else:grid_ok &= np.max(abs(r[:,2]-sweep))<1e-8 and np.max(abs(r[:,1]-(1+0.5*(j-1))))<1e-8
    check('Eight raw SPICE curves have valid sizes, finite data and expected voltages',grid_ok)
    d=np.vstack([np.column_stack([np.full(len(r),j+1),np.arange(1,len(r)+1),r[:,1:]]) for j,r in enumerate(raw)])
    t,o=raw[0],raw[4]
    tm=(t[:,1]>=1.7-1e-10)&(t[:,1]<=2.7+1e-10);om=(o[:,2]>=1.6-1e-10)&(o[:,2]<=3+1e-10)
    tf=line_fit(t[tm,1],np.sqrt(t[tm,3]));of=line_fit(o[om,2],o[om,3])
    vth=-tf[1]/tf[0];lam=of[0]/of[1];beta=2*tf[0]**2/(1+lam*t[tm,2].mean());est=np.array([vth,beta,lam])
    ref=np.array([1.2,.002,.02]);pcsv=csv('parameters_MODEL_ONLY.csv');mat=loadmat(p/'results.mat',simplify_cells=True)
    est_mat=np.array([mat['p']['vth_V'],mat['p']['beta_A_per_V2'],mat['p']['lambda_per_V']])
    check('Independent centred-OLS parameter estimates agree with returned estimates',np.all(abs(est-pcsv[:,1])<np.array([1e-13,1e-15,1e-13])),{'independent_estimates':est.tolist(),'differences':(est-pcsv[:,1]).tolist()})
    check('Parameter CSV reference, error and relative-error columns are arithmetically consistent',
          close(pcsv[:,2],ref) and close(pcsv[:,3],pcsv[:,1]-ref) and close(pcsv[:,4],(pcsv[:,1]-ref)/ref))
    check('MAT parameters and fit coefficients agree with CSV and independent fits',close(est_mat,pcsv[:,1]) and close(mat['tf'],tf) and close(mat['of'],of))
    check('Saved transfer/output fitting subsets equal original raw rows',close(csv('transfer_training_points.csv'),t[tm]) and close(csv('output_training_points.csv'),o[om]))
    check('Both fitting windows satisfy the educational saturation condition',
          np.all((t[tm,1]>vth)&(t[tm,2]>=t[tm,1]-vth)) and np.all((o[om,1]>vth)&(o[om,2]>=o[om,1]-vth)))
    fit=np.zeros(len(d),dtype=bool);fit[:len(t)]=tm
    offset=sum(len(r) for r in raw[:4]);fit[offset:offset+len(o)]=om
    keys=np.rint(d[:,2:4]*1e9).astype(np.int64)
    train_keys=set(map(tuple,keys[fit]));used=np.array([tuple(k) in train_keys for k in keys])
    unique_keys,first=np.unique(keys,axis=0,return_index=True);held=first[~used[first]]
    unique_held=np.zeros(len(d),bool);unique_held[held]=True
    split=np.where(fit,1,np.where(used,2,0))
    counts={'raw_rows':len(d),'unique_bias_points':len(unique_keys),'direct_fit_rows':int(fit.sum()),'unique_fit_bias_points':len(train_keys),
            'all_rows_at_fit_biases':int(used.sum()),'heldout_rows':int((~used).sum()),'unique_heldout_bias_points':len(held)}
    check('Bias-point grouping and all partition counts recompute correctly',counts==dict(raw_rows=1078,unique_bias_points=1066,direct_fit_rows=108,unique_fit_bias_points=107,all_rows_at_fit_biases=109,heldout_rows=969,unique_heldout_bias_points=959),counts)
    check('No fitting bias occurs in unique held-out data',not any(tuple(k) in train_keys for k in keys[held]))
    pred=current(d[:,2],d[:,3],est_mat);err=pred-d[:,4];tol=1e-10+1e-6*abs(d[:,4]);published=csv('all_predictions_and_split.csv')
    check('All saved raw columns and split flags match independent reconstruction',close(published[:,:5],d) and np.array_equal(published[:,8],split) and np.array_equal(published[:,9],unique_held))
    check('All 1078 predictions, residuals and tolerances match piecewise reconstruction',close(published[:,5],pred) and close(published[:,6],err,rtol=0) and close(published[:,7],tol))
    check('MAT arrays and grouping match the original rows and reconstructed partition',close(mat['allData'],d) and np.array_equal(mat['fitDirect'],fit) and np.array_equal(mat['usedBias'],used)
          and np.array_equal(mat['uniqueHeld'],unique_held) and np.array_equal(mat['heldRows']-1,held) and close(mat['pred'],pred) and close(mat['err'],err,rtol=0))
    hr=err[held];hi=d[held,4]
    metrics=np.array([len(hr),max(abs(hr)),np.sqrt(np.mean(hr**2)),np.sqrt(np.mean(hr**2))/max(abs(hi)),np.all(abs(hr)<=tol[held])])
    check('Unique-held-out CSV and MAT metrics recompute consistently',close(csv('heldout_unique_summary.csv')[0],metrics,atol=2e-15) and close(mat['metrics'],metrics,atol=2e-15))
    independent_err=current(d[:,2],d[:,3],est)-d[:,4]
    check('Independent refit predicts the same held-out currents and passes unchanged tolerance',np.max(abs(independent_err[held]-hr))<1e-16 and np.all(abs(independent_err[held])<=tol[held]))
    per=[]
    for j in range(1,9):
        k=(d[:,0]==j)&~used;ee=err[k];ii=d[k,4]
        per.append([j,k.sum(),max(abs(ee)),np.sqrt(np.mean(ee**2)),max(abs(ii)),np.all(abs(ee)<=tol[k])])
    check('All eight per-curve held-out statistics recompute correctly',close(csv('heldout_per_case.csv'),per))
    candidates=[];tc=[];oc=[]
    for j,L in enumerate([0,.02,.05]):
        b=2*mat['tf'][0]**2/(1+L*3);pp=np.array([est_mat[0],b,L]);tt=current(t[:,1],t[:,2],pp);oo=current(o[:,1],o[:,2],pp)
        tc.append(tt);oc.append(oo);candidates.append([j+1,L,b,np.sqrt(np.mean((tt-t[:,3])**2)),np.sqrt(np.mean((oo-o[:,3])**2))])
    tc=np.array(tc).T;oc=np.array(oc).T;candidates=np.array(candidates)
    check('Identifiability candidate parameters, curves and residual statistics match',close(csv('identifiability_candidates.csv'),candidates) and close(mat['candidates'],candidates)
          and close(csv('identifiability_transfer_curves.csv'),np.column_stack([t[:,1],t[:,3],tc])) and close(csv('identifiability_output_curves.csv'),np.column_stack([o[:,2],o[:,3],oc])))
    max_tc=float(np.max(np.ptp(tc,axis=1)));max_oc=float(np.max(abs(oc[:,0]-oc[:,2])))
    check('Candidate transfer curves coincide while output curves differ',max_tc<1e-14 and max_oc>1e-6,{'max_transfer_difference_A':max_tc,'max_output_difference_A':max_oc})
    knownchecks=np.array([len(d)==1078 and len(unique_keys)==1066,tm.sum()>=3 and om.sum()>=3,
        np.all((t[tm,1]>vth)&(t[tm,2]>=t[tm,1]-vth)),np.all((o[om,1]>vth)&(o[om,2]>=o[om,1]-vth)),
        np.isfinite(est).all() and np.all(est>0),abs(est[0]-ref[0])<1e-6,abs(est[1]-ref[1])<1e-8,abs(est[2]-ref[2])<1e-6,
        not any(tuple(k) in train_keys for k in keys[held]),len(train_keys)==107 and len(held)==959,np.all(abs(hr)<=tol[held]),max_tc<1e-14,max_oc>1e-6])
    check('All 13 original self-check conditions independently hold',knownchecks.all() and np.array_equal(csv('self_checks.csv')[:,1],knownchecks) and np.array_equal(mat['checks'],knownchecks))
    figs=sorted(p.glob('*.png'));pngs_ok=len(figs)==5
    for f in figs:
        with Image.open(f) as im: im.verify()
    check('Five PNG files decode and graphics-error log is empty',pngs_ok and (p/'GRAPHICS_ERRORS.txt').stat().st_size==0)
    known_err=current(d[:,2],d[:,3],ref)-d[:,4]
    report={'source':'Stage3_result_20260920_172044.zip','execution':'Python audit only; MATLAB/ngspice not rerun here',
       'checks':checks,'passed':sum(c['passed'] for c in checks),'total':len(checks),'all_passed':all(c['passed'] for c in checks),
       'parameters_order':['Vth_V','beta_A_per_V2','lambda_per_V'],'independent_estimates':est.tolist(),'returned_estimates':est_mat.tolist(),
       'known_educational_parameters':ref.tolist(),'counts':counts,
       'heldout_metrics':dict(n=len(held),max_abs_error_A=float(metrics[1]),rmse_A=float(metrics[2]),max_abs_error_pA=float(metrics[1]*1e12),rmse_pA=float(metrics[2]*1e12),
           max_error_to_tolerance_ratio=float(np.max(abs(hr)/tol[held])),all_within_unchanged_tolerance=bool(metrics[4])),
       'known_parameter_current_max_difference_A':float(max(abs(known_err))),
       'identifiability':dict(max_transfer_difference_A=max_tc,max_output_difference_A=max_oc),
       'caveats':['Known educational MOS1 model; fitting windows are model-informed, not blind identification.',
                  'Raw points are deterministic simulation samples from the same device/model, not independent physical measurements.',
                  'No instrument accuracy, empirical calibration traceability, hardware validation, model-mismatch robustness or uncertainty-coverage claim.'],
       'visual_review':'Separate manual image inspection is required; this script validates only file decoding.'}
    (out/'audit_results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    np.savetxt(out/'parameter_refit.csv',np.column_stack([np.arange(1,4),est_mat,est,est-est_mat]),delimiter=',',header='parameter_id,returned,independent_centred_OLS,independent_minus_returned',comments='',fmt='%.17g')
    np.savetxt(out/'heldout_refit.csv',np.column_stack([d[held,:],pred[held],hr,tol[held]]),delimiter=',',header='case_id,source_row,VGS_V,VDS_V,I_SPICE_A,I_predicted_A,predicted_minus_SPICE_A,tolerance_A',comments='',fmt='%.17g')
    print(json.dumps({k:v for k,v in report.items() if k not in ['checks','caveats']},indent=2))
    for c in checks:
        if not c['passed']:print('FAIL:',c)
    return 0 if report['all_passed'] else 1
if __name__=='__main__':sys.exit(main())
