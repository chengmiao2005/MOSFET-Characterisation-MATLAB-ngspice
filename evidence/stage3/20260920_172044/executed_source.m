function outdir = RUN_STAGE3()
% Stage 3: identify educational MOS1 parameters from VERIFIED USER SPICE outputs.
% Run with RUN_STAGE3. Base MATLAB, intended for R2019b+; no ngspice call here.
% SOURCE: user's ngspice-47 return 20260920_165426. NOT physical measurements.
% MATLAB execution of this new file is pending the user's run; see TEST_STATUS.md.
% No optimization toolbox, network, hardware, or changes to earlier stages.
root = fileparts(mfilename('fullpath'));
tag = datestr(now,'yyyymmdd_HHMMSS');
outdir = fullfile(root,'outputs_stage3',tag); n=0;
while exist(outdir,'dir'), n=n+1; outdir=fullfile(root,'outputs_stage3',sprintf('%s_%03d',tag,n)); end
[ok,msg]=mkdir(outdir); assert(ok,'Cannot create output: %s',msg);
copyfile(fullfile(root,'RUN_STAGE3.m'),fullfile(outdir,'executed_source.m'));
copyfile(fullfile(root,'data'),fullfile(outdir,'input_snapshot'));
write_text(fullfile(outdir,'STATUS.txt'),{'STAGE3_STATUS=STARTED'; ...
    'SPICE_EXECUTED_THIS_STAGE=NO_REUSED_USER_OUTPUTS'});
try
    run_analysis(root,outdir);
catch ME
    write_text(fullfile(outdir,'STATUS.txt'),{'STAGE3_STATUS=FAILED'; ...
        'SPICE_EXECUTED_THIS_STAGE=NO_REUSED_USER_OUTPUTS'; ['ERROR=' ME.message]});
    write_text(fullfile(outdir,'ERROR_REPORT.txt'),{getReport(ME,'extended','hyperlinks','off')});
    fprintf(2,'\nStage 3 stopped: %s\nResults/logs have been retained.\n',ME.message);
end
[~,folder]=fileparts(outdir);
zipPath=fullfile(root,['Stage3_result_' folder '.zip']);
try
    zip(zipPath,{folder},fileparts(outdir));
    fprintf('\nUpload this result ZIP: %s\n',zipPath);
catch ME
    write_text(fullfile(outdir,'ZIP_ERROR.txt'),{ME.message});
    fprintf(2,'ZIP could not be created. Compress this folder manually: %s\n',outdir);
end
fprintf('\nResult folder: %s\n',outdir);
end

function run_analysis(root,outdir)
% Fit windows fixed before this stage; selected for a known educational model.
% This is NOT blind identification. Truth is used only AFTER fitting to score it.
cfg=struct('stage','3.0','data_origin','USER_NGSPICE47_SIMULATION_20260920_165426', ...
    'transfer_fit_V',[1.7 2.7],'output_fit_V',[1.6 3.0], ...
    'candidate_lambda_per_V',[0 0.02 0.05], ...
    'absolute_current_tolerance_A',1e-10,'relative_current_tolerance',1e-6, ...
    'bias_key_scale',1e9);
write_text(fullfile(outdir,'config.json'),{jsonencode(cfg)});
files=[{'transfer_spice.dat'}, arrayfun(@(i)sprintf('output_gate_%d_spice.dat',i),1:6,'UniformOutput',false), {'low_vds_spice.dat'}];
A=cell(8,1); allData=zeros(0,5); fitDirect=false(0,1);
for j=1:8
    A{j}=read_spice(fullfile(root,'data','spice_case',files{j}));
    a=A{j}; N=121; if j==1 || j==8, N=176; end
    assert(isequal(size(a),[N 4]) && all(isfinite(a(:))),'Invalid raw data in %s.',files{j});
      if j==1 || j==8
        voltageGrid=(0:0.02:3.5)'; fixedV=3; if j==8,fixedV=0.2;end
        assert(max(abs(a(:,1)-voltageGrid))<1e-8 && max(abs(a(:,2)-voltageGrid))<1e-8 ...
            && max(abs(a(:,3)-fixedV))<1e-8,'Wrong voltage grid in %s.',files{j});
    else
        voltageGrid=(0:0.025:3)'; fixedG=1+0.5*(j-2);
        assert(max(abs(a(:,1)-voltageGrid))<1e-8 && max(abs(a(:,3)-voltageGrid))<1e-8 ...
            && max(abs(a(:,2)-fixedG))<1e-8,'Wrong voltage grid in %s.',files{j});
    end
    direct=false(N,1);
    if j==1, direct=in_window(a(:,2),cfg.transfer_fit_V); end
    if j==5, direct=in_window(a(:,3),cfg.output_fit_V); end
    allData=[allData; j*ones(N,1), (1:N)', a(:,2:4)]; %#ok<AGROW>
    fitDirect=[fitDirect; direct]; %#ok<AGROW>
end
% Only these two subsets enter the estimator. No config truth is passed in.
t=A{1}; o=A{5}; tm=in_window(t(:,2),cfg.transfer_fit_V); om=in_window(o(:,3),cfg.output_fit_V);
[p,tf,of]=estimate_parameters(t(tm,:),o(om,:));
truth=[1.2;0.002;0.02]; est=[p.vth_V;p.beta_A_per_V2;p.lambda_per_V];
write_csv(fullfile(outdir,'parameters_MODEL_ONLY.csv'), ...
    {'parameter_id','estimated','known_educational_model','estimate_minus_reference','relative_error'}, ...
    [(1:3)',est,truth,est-truth,(est-truth)./truth]);
write_text(fullfile(outdir,'PARAMETER_NAMES.txt'), ...
    {'1: Vth [V]';'2: beta [A/V^2], NOT small-signal gm';'3: lambda [1/V]'});

% Remove shared sweep intersections from held-out data by the BIAS POINT,
% not by file name. Deduplicate held-out intersections for aggregate metrics.
keys=round(allData(:,3:4)*cfg.bias_key_scale);
trainingKeys=unique(keys(fitDirect,:),'rows');
usedBias=ismember(keys,trainingKeys,'rows');
[uniqueKeys,uniqueRows]=unique(keys,'rows');
heldRows=uniqueRows(~usedBias(uniqueRows));
split=zeros(size(fitDirect)); split(fitDirect)=1; split(usedBias & ~fitDirect)=2;
% split 0 = held out, 1 = directly fitted, 2 = excluded training-bias duplicate.
uniqueHeld=false(size(fitDirect)); uniqueHeld(heldRows)=true;
pred=channel_current(allData(:,3),allData(:,4),p); err=pred-allData(:,5);
tol=cfg.absolute_current_tolerance_A+cfg.relative_current_tolerance*abs(allData(:,5));
write_csv(fullfile(outdir,'all_predictions_and_split.csv'), ...
    {'case_id','source_row','VGS_V','VDS_V','I_SPICE_A','I_predicted_A', ...
     'predicted_minus_SPICE_A','tolerance_A','split_code','unique_heldout'}, ...
    [allData,pred,err,tol,split,double(uniqueHeld)]);
write_csv(fullfile(outdir,'transfer_training_points.csv'), ...
    {'sweep_V','VGS_V','VDS_V','I_SPICE_A'},t(tm,:));
write_csv(fullfile(outdir,'output_training_points.csv'), ...
    {'sweep_V','VGS_V','VDS_V','I_SPICE_A'},o(om,:));
hr=err(heldRows); hi=allData(heldRows,5);
metrics=[numel(hr),max(abs(hr)),sqrt(mean(hr.^2)),sqrt(mean(hr.^2))/max(abs(hi)),all(abs(hr)<=tol(heldRows))];
write_csv(fullfile(outdir,'heldout_unique_summary.csv'), ...
    {'unique_heldout_points','max_abs_error_A','rmse_A','rmse_over_max_abs_current','all_within_tolerance'},metrics);
perCase=zeros(8,6);
for j=1:8
    k=allData(:,1)==j & ~usedBias;
    perCase(j,:)=[j,sum(k),max(abs(err(k))),sqrt(mean(err(k).^2)),max(abs(allData(k,5))),all(abs(err(k))<=tol(k))];
end
write_csv(fullfile(outdir,'heldout_per_case.csv'), ...
    {'case_id','heldout_rows_in_case','max_abs_error_A','rmse_A','max_abs_reference_current_A','all_within_tolerance'},perCase);
write_text(fullfile(outdir,'SPLIT_NOTES.txt'),{ ...
    sprintf('Raw rows: %d; distinct bias points: %d.',size(allData,1),size(uniqueKeys,1)); ...
    sprintf('Direct fitting rows: %d; unique fitting bias points: %d.',sum(fitDirect),size(trainingKeys,1)); ...
    sprintf('Rows excluded because they share a fitted bias: %d.',sum(usedBias)); ...
    sprintf('Held-out rows: %d; distinct held-out bias points used for aggregate metrics: %d.',sum(~usedBias),numel(heldRows)); ...
    'Bias keys use 1e-9 V rounding ONLY for grouping intersections, not for fitting.'; ...
    'Repeated bias points are excluded/deduplicated, not additional experiments.'; ...
    'The fit windows were chosen for a known educational model, not blind identification.'; ...
    'Held-out points are same-model deterministic simulations, not independent physical evidence.'});

% Identifiability demonstration: one fixed-VDS transfer curve only determines
% beta*(1+lambda*VDS). Multiple beta/lambda pairs reproduce that transfer curve.
L=cfg.candidate_lambda_per_V(:); candidates=zeros(numel(L),5);
transferCandidates=zeros(size(t,1),numel(L)); outputCandidates=zeros(size(o,1),numel(L));
for j=1:numel(L)
    q=p; q.lambda_per_V=L(j); q.beta_A_per_V2=2*tf(1)^2/(1+L(j)*t(1,3));
    transferCandidates(:,j)=channel_current(t(:,2),t(:,3),q);
    outputCandidates(:,j)=channel_current(o(:,2),o(:,3),q);
    candidates(j,:)=[j,L(j),q.beta_A_per_V2, ...
        sqrt(mean((transferCandidates(:,j)-t(:,4)).^2)),sqrt(mean((outputCandidates(:,j)-o(:,4)).^2))];
end
write_csv(fullfile(outdir,'identifiability_candidates.csv'), ...
    {'candidate_id','lambda_per_V','beta_A_per_V2','transfer_rmse_A','output_curve_rmse_A'},candidates);
write_csv(fullfile(outdir,'identifiability_transfer_curves.csv'), ...
    {'VGS_V','I_SPICE_A','lambda_0_A','lambda_0p02_A','lambda_0p05_A'},[t(:,2),t(:,4),transferCandidates]);
write_csv(fullfile(outdir,'identifiability_output_curves.csv'), ...
    {'VDS_V','I_SPICE_A','lambda_0_A','lambda_0p02_A','lambda_0p05_A'},[o(:,3),o(:,4),outputCandidates]);

checkNames={'Raw row and unique-bias counts are correct'; ...
    'Both fit windows contain enough distinct voltage points'; ...
    'Transfer fit is in saturation under extracted parameters'; ...
    'Output fit is in saturation under extracted parameters'; ...
    'Estimated parameters are positive and finite'; ...
    'Vth agrees with educational reference within 1e-6 V'; ...
    'beta agrees with educational reference within 1e-8 A/V^2'; ...
    'lambda agrees with educational reference within 1e-6 1/V'; ...
    'No fitted bias appears in unique held-out data'; ...
    'Split has 107 unique fitting and 959 unique held-out bias points'; ...
    'All unique held-out points satisfy unchanged current tolerance'; ...
    'Different beta/lambda pairs produce identical transfer current'; ...
    'Those pairs produce distinguishable output current'};
finiteEst=all(isfinite(est)) && all(est>0);
checks=[size(allData,1)==1078 && size(uniqueKeys,1)==1066; ...
    nnz(tm)>=3 && nnz(om)>=3; ...
    all(t(tm,2)-p.vth_V>0 & t(tm,3)>=t(tm,2)-p.vth_V); ...
    all(o(om,2)-p.vth_V>0 & o(om,3)>=o(om,2)-p.vth_V); ...
    finiteEst;abs(est(1)-truth(1))<1e-6;abs(est(2)-truth(2))<1e-8;abs(est(3)-truth(3))<1e-6; ...
    ~any(ismember(keys(heldRows,:),trainingKeys,'rows')); ...
    size(trainingKeys,1)==107 && numel(heldRows)==959; ...
    all(abs(hr)<=tol(heldRows)); ...
    max(max(abs(transferCandidates-transferCandidates(:,1))))<1e-14; ...
    max(abs(outputCandidates(:,1)-outputCandidates(:,3)))>1e-6];
write_csv(fullfile(outdir,'self_checks.csv'),{'check_id','passed'},[(1:numel(checks))',double(checks)]);
write_text(fullfile(outdir,'CHECK_NAMES.txt'),checkNames);

plotErrors={};
try
    f=figure('Name','01 Extract threshold','NumberTitle','off');
    plot(t(tm,2),sqrt(t(tm,4)),'o','DisplayName','Fitted SPICE points'); hold on;
    xx=linspace(min(p.vth_V,1.2)-.05,2.75,160)';
    plot(xx,polyval(tf,xx),'-','DisplayName','Square-root line fit'); yline(0,':');grid on;
    xlabel('V_{GS} (V)');ylabel('sqrt(I_D) (sqrt(A))');legend('Location','northwest');
    title('01 | Vth extraction from SPICE simulation - not a measured device');
    saveas(f,fullfile(outdir,'01_threshold_extraction_SPICE.png'));
catch ME,plotErrors{end+1}=ME.message;end %#ok<AGROW>
try
    f=figure('Name','02 Extract lambda','NumberTitle','off');
    plot(o(:,3),o(:,4)*1e3,'-','DisplayName','Complete SPICE output curve');hold on;
    plot(o(om,3),o(om,4)*1e3,'o','DisplayName','Fitted saturation points');
    plot(o(:,3),polyval(of,o(:,3))*1e3,'--','DisplayName','Line extrapolation');grid on;
    xlabel('V_{DS} (V)');ylabel('I_D (mA)');legend('Location','northwest');
    title('02 | lambda = slope/intercept, using VGS = 2.5 V');
    saveas(f,fullfile(outdir,'02_lambda_extraction_SPICE.png'));
catch ME,plotErrors{end+1}=ME.message;end %#ok<AGROW>
try
    f=figure('Name','03 Held-out current residual','NumberTitle','off');
    plot(hi*1e3,hr*1e12,'.');grid on;
    xlabel('Held-out SPICE current (mA)');ylabel('Extracted-model prediction minus SPICE (pA)');
    title(sprintf('03 | %d distinct held-out bias points - same-model check only',numel(heldRows)));
    saveas(f,fullfile(outdir,'03_heldout_residual_SPICE.png'));
catch ME,plotErrors{end+1}=ME.message;end %#ok<AGROW>
try
    f=figure('Name','04 Transfer ambiguity','NumberTitle','off');
    plot(t(:,2),transferCandidates*1e3,'LineWidth',1.2);grid on;
    xlabel('V_{GS} (V)');ylabel('Predicted I_D (mA)');
    legend('lambda=0','lambda=0.02','lambda=0.05','Location','northwest');
    title('04 | Different beta/lambda pairs: the three transfer curves overlap');
    saveas(f,fullfile(outdir,'04_nonunique_transfer_MODEL.png'));
catch ME,plotErrors{end+1}=ME.message;end %#ok<AGROW>
try
    f=figure('Name','05 Output resolves ambiguity','NumberTitle','off');
    plot(o(:,3),outputCandidates*1e3,'LineWidth',1.2);hold on;
    plot(o(1:6:end,3),o(1:6:end,4)*1e3,'o');grid on;
    xlabel('V_{DS} (V)');ylabel('I_D (mA)');
    legend('lambda=0','lambda=0.02','lambda=0.05','SPICE sample points','Location','northwest');
    title('05 | Output-sweep information separates the parameter pairs');
    saveas(f,fullfile(outdir,'05_output_separates_parameters_MODEL.png'));
catch ME,plotErrors{end+1}=ME.message;end %#ok<AGROW>
write_text(fullfile(outdir,'GRAPHICS_ERRORS.txt'),plotErrors(:));
status='PASS_SAME_MODEL_POSTPROCESSING';
if ~all(checks),status='CHECK_FAILED';elseif ~isempty(plotErrors),status='NUMERICS_PASS_GRAPHICS_ERRORS';end
summary={['STAGE3_STATUS=' status];sprintf('SELF_CHECKS=%d/%d',sum(checks),numel(checks)); ...
    ['MATLAB=' version];'SOURCE_SPICE_RUN=USER_RETURN_20260920_165426'; ...
    'SPICE_EXECUTED_THIS_STAGE=NO_REUSED_USER_OUTPUTS'; ...
    sprintf('Vth_estimate_V=%.12g',p.vth_V);sprintf('beta_estimate_A_per_V2=%.12g',p.beta_A_per_V2); ...
    sprintf('lambda_estimate_per_V=%.12g',p.lambda_per_V); ...
    sprintf('unique_fitting_bias_points=%d',size(trainingKeys,1)); ...
    sprintf('unique_heldout_bias_points=%d',numel(heldRows)); ...
    sprintf('heldout_max_abs_error_A=%.12g',metrics(2));sprintf('heldout_rmse_A=%.12g',metrics(3)); ...
    sprintf('graphics_errors=%d',numel(plotErrors)); ...
    'No new ngspice execution. Reused raw outputs have been copied to input_snapshot.'; ...
    'No physical device, wafer test, instrumental pA accuracy, or uncertainty coverage demonstrated.'; ...
    'Known educational-model references score estimates; fit windows are model-informed.'; ...
    'One transfer curve identifies beta*(1+lambda*VDS), not beta and lambda separately.'};
write_text(fullfile(outdir,'SUMMARY.txt'),summary);
write_text(fullfile(outdir,'STATUS.txt'),summary(1:5));
save(fullfile(outdir,'results.mat'),'cfg','p','truth','tf','of','allData','pred','err', ...
    'fitDirect','usedBias','uniqueHeld','heldRows','metrics','candidates','checks','status');
for j=1:numel(summary),fprintf('%s\n',summary{j});end
end

function [p,tf,of]=estimate_parameters(transfer,output)
% No true Vth, beta or lambda is accepted by this function.
assert(size(transfer,1)>=3 && size(output,1)>=3,'Insufficient fitting data.');
assert(all(transfer(:,4)>0) && all(output(:,4)>0),'Nonpositive fitting currents.');
assert(max(transfer(:,3))-min(transfer(:,3))<1e-8 && max(output(:,2))-min(output(:,2))<1e-8, ...
    'Expected fixed-VDS/fixed-VGS curves.');
tf=polyfit(transfer(:,2),sqrt(transfer(:,4)),1);
of=polyfit(output(:,3),output(:,4),1);
assert(tf(1)>0 && of(2)>0,'Invalid fitting slope or current intercept.');
p.vth_V=-tf(2)/tf(1);
p.lambda_per_V=of(1)/of(2);
p.beta_A_per_V2=2*tf(1)^2/(1+p.lambda_per_V*mean(transfer(:,3)));
end
function I=channel_current(vg,vd,p)
u=max(vg-p.vth_V,0); w=min(vd,u);
I=p.beta_A_per_V2*(u.*w-w.^2/2).*(1+p.lambda_per_V*vd);
end
function mask=in_window(x,w)
mask=x>=w(1)-1e-10 & x<=w(2)+1e-10;
end
function a=read_spice(path)
f=fopen(path,'r');assert(f>=0,'Cannot open %s',path);
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
head=fgetl(f);assert(ischar(head) && contains(lower(head),'idrain'),'Unexpected raw SPICE header.');
v=textscan(f,'%f %f %f %f','CollectOutput',true);a=v{1};
end
function write_text(path,lines)
f=fopen(path,'w','n','UTF-8');assert(f>=0,'Cannot write %s',path);
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
for j=1:numel(lines),fprintf(f,'%s\n',lines{j});end
end
function write_csv(path,headers,a)
f=fopen(path,'w');assert(f>=0,'Cannot write %s',path);
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',strjoin(headers,','));
fmt=[repmat('%.17g,',1,size(a,2)-1),'%.17g\n'];fprintf(f,fmt,a');
end
