"""Independently audit the user's Stage 2B return, without executing MATLAB code.
Dependencies: Python 3.10+, numpy, scipy. Numerical verification, not hardware validation.
Usage: python audit_stage2b.py RESULTS_DIRECTORY [OUTPUT_DIRECTORY] [ORIGINAL_STARTER_ZIP]
"""
from pathlib import Path
import csv, hashlib, json, re, sys, zipfile
import numpy as np
from scipy.io import loadmat


def main(src: Path, out: Path, original: Path | None = None) -> None:
    out.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(name, condition, detail=''):
        checks.append({'name': name, 'passed': bool(condition), 'detail': detail})
    def close(a,b,atol=2e-17,rtol=2e-13):
        return np.shape(a)==np.shape(b) and np.allclose(a,b,atol=atol,rtol=rtol)
    def read_csv(name):
        return np.loadtxt(src/name, delimiter=',', skiprows=1, ndmin=2)
    def model(vg,vd,c):
        # A separate piecewise implementation rather than copying the MATLAB expression.
        vg,vd=np.broadcast_arrays(vg,vd); over=vg-c['vth_V']
        ans=np.zeros(vg.shape,dtype=float)
        on=over>0; sat=on & (vd>=over); lin=on & ~sat
        ans[sat]=0.5*c['beta_A_per_V2']*over[sat]**2*(1+c['lambda_per_V']*vd[sat])
        ans[lin]=c['beta_A_per_V2']*(over[lin]*vd[lin]-0.5*vd[lin]**2)*(1+c['lambda_per_V']*vd[lin])
        return ans
    def fit(vg,cur):
        k=(vg>=1.7-1e-12)&(vg<=2.7+1e-12)
        # Solve a centered least-squares line independently of MATLAB polyfit.
        x,y=vg[k],np.sqrt(cur[k]); xc=x-x.mean()
        slope=np.dot(xc,y-y.mean())/np.dot(xc,xc); b=y.mean()-slope*x.mean()
        return -b/slope
    c=json.loads((src/'config.json').read_text())
    st=(src/'STATUS.txt').read_text(); version=(src/'spice_case/engine_version.txt').read_text()
    log=(src/'spice_case/ngspice_run.log').read_text()
    check('Reported actual-execution comparison pass','SPICE_STATUS=EXECUTED_COMPARISON_PASS' in st)
    check('Engine version and successful version query present', 'ngspice-47' in version and 'exit status: 0' in version)
    check('All eight analyses completed in ngspice log', re.findall(r'No\. of Data Rows\s*:\s*(\d+)',log)==['176']+['121']*6+['176'] and 'ngspice-47 done' in log)
    check('No error/fatal or convergence failure in engine log',not re.search(r'\b(error|fatal|failed)\b',log,re.I))
    check('Original absolute and relative tolerances unchanged',c['spice_abs_tolerance_A']==1e-10 and c['spice_rel_tolerance']==1e-6)
    if original:
        with zipfile.ZipFile(original) as z:
            for local, old in [('executed_source.m','PSI_MOSFET_Stage2.m'),('executed_launcher.m','RUN_STAGE2B.m'),('spice_case/mosfet_level1.cir','spice_case/mosfet_level1.cir')]:
                names=[n for n in z.namelist() if n.endswith('/'+old)]
                check('Byte-identical to starter: '+local,len(names)==1 and (src/local).read_bytes()==z.read(names[0]))
    files=['transfer_spice.dat']+[f'output_gate_{i}_spice.dat' for i in range(1,7)]+['low_vds_spice.dat']
    table=read_csv('SPICE_comparison_summary.csv'); metrics=[]; total_points=0; point_pass=0
    for j,name in enumerate(files,1):
        a=np.loadtxt(src/'spice_case'/name,skiprows=1)
        n=176 if j in (1,8) else 121
        check(f'Case {j}: finite four-column raw SPICE file',a.shape==(n,4) and np.isfinite(a).all())
        if j in (1,8):
            vv=np.arange(176)*.02
            check(f'Case {j}: sweep and terminal voltages',close(a[:,0],vv,atol=1e-12) and close(a[:,1],vv,atol=1e-12) and np.allclose(a[:,2],3 if j==1 else .2,atol=1e-12,rtol=0))
        else:
            vv=np.arange(121)*.025
            check(f'Case {j}: sweep and terminal voltages',close(a[:,0],vv,atol=1e-12) and close(a[:,2],vv,atol=1e-12) and np.allclose(a[:,1],1+.5*(j-2),atol=1e-12,rtol=0))
        ref=model(a[:,1],a[:,2],c); err=a[:,3]-ref
        tol=c['spice_abs_tolerance_A']+c['spice_rel_tolerance']*np.abs(ref)
        expected=np.column_stack([a,ref,err,tol]); got=read_csv(f'SPICE_comparison_{j:02d}.csv')
        check(f'Case {j}: raw data preserved in CSV',np.array_equal(got[:,:4],a))
        check(f'Case {j}: model, residual and tolerance recomputed',close(got[:,4:],expected[:,4:]))
        metric=[j,n,float(np.max(abs(err))),float(np.sqrt(np.mean(err**2))),int(np.all(abs(err)<=tol))]
        check(f'Case {j}: summary statistics recomputed',close(table[j-1],np.array(metric)))
        check(f'Case {j}: every point satisfies ORIGINAL tolerance',np.all(abs(err)<=tol))
        metrics.append({'case_id':j,'raw_file':name,'points':n,'max_abs_error_A':metric[2],'rmse_A':metric[3],'passed':bool(metric[4]),'max_error_over_tolerance':float(np.max(abs(err)/tol))})
        total_points+=n;point_pass+=int(np.sum(abs(err)<=tol))
    vg=np.arange(176)*.02; ideal=model(vg,3.,c); both=ideal*1.008+15e-6
    curves=np.column_stack([ideal,ideal*1.008,ideal+15e-6,both,(both-15e-6)/1.008])
    thresholds=np.array([fit(vg,curves[:,i]) for i in range(5)])
    low=model(vg,.2,c);lowth=fit(vg,low)
    check('Stage2A currents independently reproduced',close(read_csv('mechanism_curves_MODEL.csv'),np.column_stack([vg,curves])))
    check('Stage2A threshold table reproduced',close(read_csv('mechanism_summary_MODEL.csv')[:,1],thresholds,atol=1e-12))
    check('Low-VDS counterexample curve reproduced',close(read_csv('low_vds_counterexample_MODEL.csv'),np.column_stack([vg,ideal,low])))
    check('Nine original mechanism self-check flags passed',np.array_equal(read_csv('mechanism_self_checks.csv'),np.column_stack([np.arange(1,10),np.ones(9)])))
    m=loadmat(src/'results.mat',simplify_cells=True)
    check('MAT config equals JSON config',all((np.array_equal(m['cfg'][k],v) if isinstance(v,list) else m['cfg'][k]==v) for k,v in c.items()))
    check('MAT arrays and estimates independently reproduced',close(m['vgs'],vg) and close(m['currents'],curves) and close(m['lowI'],low) and close(m['thresholds'],thresholds,atol=1e-12) and abs(m['lowThreshold']-lowth)<1e-12)
    check('MAT result status and checks match',m['spiceStatus']=='EXECUTED_COMPARISON_PASS' and np.array_equal(m['checks'],np.ones(9)))
    check('Plot generation error log empty',(src/'GRAPHICS_ERRORS.txt').stat().st_size==0)
    from PIL import Image
    pngs=list(src.glob('*.png'));valid=True
    for f in pngs:
        try:
            with Image.open(f) as im:im.verify()
        except Exception:valid=False
    check('Five readable returned PNGs',len(pngs)==5 and valid)
    t=np.loadtxt(src/'spice_case/transfer_spice.dat',skiprows=1); residual=t[:,3]-model(t[:,1],t[:,2],c)
    explanation=1e-12*3+1e-14
    # Explanatory check, not a subtracted baseline or a modified acceptance condition.
    check('Transfer residual consistent with specified GMIN*VDS+IS',np.max(abs(residual-explanation))<1e-16)
    digest=lambda b:hashlib.sha256(b).hexdigest()
    data={'result_directory':src.name,'actual_engines_run_by_this_audit':[],'audit_engine':'Python + NumPy + SciPy; no MATLAB/ngspice execution',
          'reported_matlab_version':'24.1.0.2537033 (R2024a)','reported_ngspice_version':'ngspice-47',
          'original_atol_A':c['spice_abs_tolerance_A'],'original_rtol':c['spice_rel_tolerance'],
          'total_compared_points':total_points,'points_within_original_tolerance':point_pass,
          'cases':metrics,'checks_passed':sum(ch['passed'] for ch in checks),'checks_total':len(checks),'checks':checks,
          'transfer_residual_A':{'min':float(residual.min()),'max':float(residual.max()),'peak_to_peak':float(np.ptp(residual)),'GMIN_times_VDS_plus_IS_A':explanation},
          'sha256':{f.relative_to(src).as_posix():digest(f.read_bytes()) for f in sorted(src.rglob('*')) if f.is_file()},
          'limitations':['Same-model implementation consistency, not independent physical validation.','No hardware, ADC, repeatability measurement, or instrumental pA precision demonstrated.','Checks are integrity and numerical checks, not independent experiments.']}
    (out/'audit_result.json').write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
    with (out/'comparison_recomputed.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(metrics[0]));w.writeheader();w.writerows(metrics)
    print(json.dumps({k:data[k] for k in ['total_compared_points','points_within_original_tolerance','checks_passed','checks_total','transfer_residual_A']},indent=2))
    failed=[ch for ch in checks if not ch['passed']]
    if failed:raise AssertionError(failed)

if __name__=='__main__':
    if len(sys.argv)<2:raise SystemExit(__doc__)
    main(Path(sys.argv[1]),Path(sys.argv[2]) if len(sys.argv)>2 else Path('audit_output'),Path(sys.argv[3]) if len(sys.argv)>3 else None)
