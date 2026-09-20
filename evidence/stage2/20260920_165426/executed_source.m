function outdir = PSI_MOSFET_Stage2(spiceExe)
% Stage 2A: isolate gain/offset effects with an exact educational model.
% Stage 2B: OPTIONAL ngspice Level-1 implementation consistency comparison.
% Usage: PSI_MOSFET_Stage2                  (2A + prepare 2B; no SPICE run)
%        PSI_MOSFET_Stage2('choose')        (select ngspice executable)
%        PSI_MOSFET_Stage2('C:\ngspice\bin\ngspice_con.exe')
% Base MATLAB, intended for R2019b+. No hardware or commercial device data.
% Default mode NEVER fabricates SPICE outputs or reports SPICE as passed.
if nargin < 1, spiceExe = ''; end
if isstring(spiceExe), spiceExe = char(spiceExe); end
assert(ischar(spiceExe) && (isrow(spiceExe) || isempty(spiceExe)), 'Provide one executable path.');
if strcmpi(spiceExe,'choose')
    [f,p] = uigetfile({'*.exe','ngspice console executable';'*','All files'}, ...
        'Select ngspice_con.exe / ngspice executable');
    if isequal(f,0), spiceExe=''; else, spiceExe=fullfile(p,f); end
end
root=fileparts(mfilename('fullpath'));
cfg=struct('version','2.0','data_origin','MODEL_ONLY_NOT_EXPERIMENT', ...
    'vth_V',1.2,'beta_A_per_V2',0.002,'lambda_per_V',0.02, ...
    'vgs_step_V',0.02,'vds_transfer_V',3.0,'low_vds_V',0.2, ...
    'fit_window_V',[1.7 2.7],'gain_error',0.008,'offset_A',15e-6, ...
    'spice_abs_tolerance_A',1e-10,'spice_rel_tolerance',1e-6);
outdir=new_folder(root);
copyfile(fullfile(root,'PSI_MOSFET_Stage2.m'),fullfile(outdir,'executed_source.m'));
write_text(fullfile(outdir,'config.json'),{jsonencode(cfg)});
spiceDir=fullfile(outdir,'spice_case'); mkdir(spiceDir);
copyfile(fullfile(root,'spice_case','mosfet_level1.cir'), ...
    fullfile(spiceDir,'mosfet_level1.cir'));
write_text(fullfile(outdir,'STATUS.txt'), ...
    {'STAGE2_STARTED';'SPICE_STATUS=NOT_RUN';'All data are models, not physical measurements.'});

% 2A: No random noise, no quantization. Isolate the mechanism before mixing errors.
vgs=(0:cfg.vgs_step_V:3.5)'; ideal=mos_current(vgs,3,cfg);
g=cfg.gain_error; b=cfg.offset_A;
labels={'Ideal','Gain only','Offset only','Gain and offset','Exact correction'};
combined=(1+g)*ideal+b;
currents=[ideal,(1+g)*ideal,ideal+b,combined,(combined-b)/(1+g)];
thresholds=NaN(5,1); fitCoef=NaN(5,2);
for j=1:5, [thresholds(j),fitCoef(j,:)]=threshold_fit(vgs,currents(:,j),cfg); end
gm=gradient(ideal,cfg.vgs_step_V); gmGain=gradient(currents(:,2),cfg.vgs_step_V);
mask=vgs>=1.7-1e-12 & vgs<=2.7+1e-12;
lowI=mos_current(vgs,cfg.low_vds_V,cfg);
[lowThreshold,lowCoef]=threshold_fit(vgs,lowI,cfg);
write_csv(fullfile(outdir,'mechanism_summary_MODEL.csv'), ...
    {'method_id','Vth_estimate_V','Vth_error_mV'}, ...
    [(1:5)' thresholds (thresholds-cfg.vth_V)*1e3]);
write_csv(fullfile(outdir,'mechanism_curves_MODEL.csv'), ...
    {'VGS_V','ideal_A','gain_only_A','offset_only_A','gain_offset_A','exact_correction_A'}, ...
    [vgs currents]);
write_csv(fullfile(outdir,'low_vds_counterexample_MODEL.csv'), ...
    {'VGS_V','I_VDS_3V_A','I_VDS_0p2V_A'},[vgs ideal lowI]);

% Packaged Python references are mathematical checks, NOT SPICE outputs.
ref=readmatrix(fullfile(root,'verification','mechanism_reference_MODEL.csv'),'NumHeaderLines',1);
refLow=readmatrix(fullfile(root,'verification','low_vds_fit_reference_MODEL.csv'),'NumHeaderLines',1);
assert(isequal(size(ref),[5 3]) && all(isfinite(ref(:))), 'Invalid reference file.');
assert(isequal(size(refLow),[1 2]) && all(isfinite(refLow(:))), 'Invalid low-VDS reference.');
checkNames={'Noiseless threshold equals model Vth'; ...
    'Pure current gain leaves square-root intercept unchanged'; ...
    'Pure current gain scales numerical gm'; ...
    'Positive current offset changes fitted threshold'; ...
    'Exact inverse correction recovers ideal current'; ...
    'Default VDS=3 fit window is saturated'; ...
    'Low VDS=0.2 fit window is NOT saturated'; ...
    'Five threshold values match Python mathematical reference'; ...
    'Low-VDS fit matches Python mathematical reference'};
checks=[abs(thresholds(1)-1.2)<1e-10; abs(thresholds(2)-thresholds(1))<1e-10; ...
    max(abs(gmGain-(1+g)*gm))<1e-12; abs(thresholds(3)-1.2)>1e-4; ...
    max(abs(currents(:,5)-ideal))<1e-14; all(vgs(mask)-1.2<=3); ...
    all(vgs(mask)-1.2>0.2); max(abs(thresholds-ref(:,2)))<1e-10; ...
    abs(lowThreshold-refLow(1,2))<1e-10];
write_csv(fullfile(outdir,'mechanism_self_checks.csv'),{'check_id','passed'}, ...
    [(1:numel(checks))' double(checks)]);
write_text(fullfile(outdir,'MECHANISM_CHECK_NAMES.txt'),checkNames);
if ~all(checks)
    write_text(fullfile(outdir,'STATUS.txt'),{'STAGE2A_CHECK_FAILED';'SPICE_STATUS=NOT_RUN'});
    error('PSI:Check','A mechanism check failed; inspect outputs, do not report success.');
end

plotErrors={};
try
    f=figure('Name','01 Error-source mechanisms','NumberTitle','off');
    bar((thresholds-cfg.vth_V)*1e3); grid on;
    set(gca,'XTick',1:5,'XTickLabel',labels); xtickangle(15);
    ylabel('Fitted Vth error (mV)'); title('01 | Error mechanisms - exact model, no noise or ADC');
    saveas(f,fullfile(outdir,'01_error_source_mechanisms_MODEL.png'));
catch ME, plotErrors{end+1}=ME.message; end %#ok<AGROW>
try
    f=figure('Name','02 Current error mechanisms','NumberTitle','off');
    plot(vgs,(currents(:,2:4)-ideal)*1e6,'LineWidth',1.2); grid on;
    xlabel('V_{GS} (V)'); ylabel('Current-reading error (microampere)');
    legend(labels(2:4),'Location','northwest');
    title('02 | Same Vth does not imply accurate current or gm');
    saveas(f,fullfile(outdir,'02_current_errors_MODEL.png'));
catch ME, plotErrors{end+1}=ME.message; end %#ok<AGROW>
try
    f=figure('Name','03 Fit-region counterexample','NumberTitle','off');
    xx=linspace(min([lowThreshold,1.2])-0.05,2.7,150);
    plot(vgs(mask),sqrt(ideal(mask)),'o',vgs(mask),sqrt(lowI(mask)),'.'); hold on;
    plot(xx,polyval(fitCoef(1,:),xx),'--',xx,polyval(lowCoef,xx),'--');
    yline(0,':'); grid on; xlabel('V_{GS} (V)'); ylabel('sqrt(I_D) (sqrt(A))');
    title('03 | The saturation-method fit is invalid at VDS = 0.2 V');
    legend('3 V: saturation points','0.2 V: triode points', ...
        '3 V extrapolation','0.2 V inappropriate extrapolation','Location','northwest');
    saveas(f,fullfile(outdir,'03_wrong_region_counterexample_MODEL.png'));
catch ME, plotErrors{end+1}=ME.message; end %#ok<AGROW>

spiceStatus='NOT_RUN_ENGINE_NOT_PROVIDED'; spiceMessage='';
if ~isempty(spiceExe)
    try
        % Explicit user-selected path only. No auto-install or network access.
        assert(exist(spiceExe,'file')==2, 'Executable not found; provide an absolute path.');
        assert(~any(ismember(spiceExe, ['"' char(10) char(13)])), 'Invalid executable path.');
        if ~ispc, assert(~any(contains(spiceExe,{'$','`'})),'Invalid executable path.'); end
        old=pwd; restore=onCleanup(@() cd(old)); cd(spiceDir);
        [vstatus,versionText]=system(sprintf('"%s" --version',spiceExe));
        write_text('engine_version.txt',{versionText; sprintf('Version command exit status: %d',vstatus)});
        command=sprintf('"%s" -b -o ngspice_run.log mosfet_level1.cir',spiceExe);
        write_text('invocation.txt',{command;['Working directory: ' spiceDir]});
        [status,console]=system(command); write_text('console.txt',{console});
        clear restore; % Restore previous MATLAB working directory.
        assert(status==0,'ngspice exit status %d; see ngspice_run.log.',status);
        [rows,transfer]=compare_spice(spiceDir,outdir,cfg);
        if all(rows(:,5)>0)
            spiceStatus='EXECUTED_COMPARISON_PASS';
        else
            spiceStatus='EXECUTED_COMPARISON_FAIL';
        end
        try
            f=figure('Name','04 SPICE transfer comparison','NumberTitle','off');
            plot(transfer(:,2),transfer(:,4)*1e3,'-', ...
                 transfer(:,2),transfer(:,5)*1e3,'--'); grid on;
            xlabel('V_{GS} (V)'); ylabel('I_D (mA)');
            legend('ngspice supply-derived current','Educational channel model','Location','northwest');
            title('04 | Shared-model implementation check - not physical validation');
            saveas(f,fullfile(outdir,'04_SPICE_transfer_COMPARISON.png'));
            f=figure('Name','05 SPICE current residual','NumberTitle','off');
            plot(transfer(:,2),(transfer(:,4)-transfer(:,5))*1e12); grid on;
            xlabel('V_{GS} (V)'); ylabel('SPICE minus channel model (pA)');
            title('05 | Residual includes omitted junction and numerical terms');
            saveas(f,fullfile(outdir,'05_SPICE_residual_COMPARISON.png'));
        catch ME, plotErrors{end+1}=ME.message; end %#ok<AGROW>
    catch ME
        spiceStatus='EXECUTION_OR_COMPARISON_ERROR'; spiceMessage=ME.message;
        warning('PSI:Spice','SPICE stage not complete: %s',ME.message);
    end
end

summary={'STAGE 2A: MATHEMATICAL ERROR-MECHANISM STUDY'; ...
    ['MATLAB: ' version]; sprintf('Mechanism checks: %d/%d passed',sum(checks),numel(checks)); ...
    'No random noise, no ADC, exact assumed correction in Stage 2A.'};
for j=1:5
    summary{end+1,1}=sprintf('%s: Vth=%.9f V, error=%+.6f mV',labels{j}, ...
        thresholds(j),(thresholds(j)-1.2)*1e3); %#ok<AGROW>
end
summary=[summary;{sprintf('Deliberately inappropriate VDS=0.2 fit: %.9f V',lowThreshold); ...
    'That last number is a method-domain counterexample, NOT a changed physical Vth.'; ...
    ['SPICE_STATUS=' spiceStatus]; ['SPICE message: ' spiceMessage]; ...
    sprintf('Graphics errors: %d',numel(plotErrors)); ...
    'SPICE comparison uses absolute/relative numerical tolerances fixed in config.'; ...
    'No hardware, real-device validation, wafer measurements, or uncertainty coverage claim.'; ...
    'Read README_CN.md before describing this work in an application.'}];
write_text(fullfile(outdir,'SUMMARY.txt'),summary);
write_text(fullfile(outdir,'GRAPHICS_ERRORS.txt'),plotErrors(:));
write_text(fullfile(outdir,'STATUS.txt'),{ ...
    sprintf('STAGE2A_CHECKS=%d/%d',sum(checks),numel(checks));['SPICE_STATUS=' spiceStatus]});
save(fullfile(outdir,'results.mat'),'cfg','vgs','currents','thresholds','lowI', ...
    'lowThreshold','gm','gmGain','checks','spiceStatus');
for k=1:numel(summary), fprintf('%s\n',summary{k}); end
fprintf('\nOutputs: %s\n',outdir);
if isempty(spiceExe)
    fprintf('SPICE has NOT run. For ngspice, later run PSI_MOSFET_Stage2(''choose'').\n');
end
end

function [rows,transfer]=compare_spice(spiceDir,outdir,c)
files=[{'transfer_spice.dat'},arrayfun(@(j)sprintf('output_gate_%d_spice.dat',j), ...
    1:6,'UniformOutput',false),{'low_vds_spice.dat'}];
rows=zeros(8,5); transfer=[]; gates=[1 1.5 2 2.5 3 3.5];
for j=1:8
    path=fullfile(spiceDir,files{j});
    assert(exist(path,'file')==2,'Missing SPICE output: %s',files{j});
    fid=fopen(path,'r'); closer=onCleanup(@() fclose(fid));
    header=fgetl(fid); assert(ischar(header),'Empty data file.');
    data=textscan(fid,'%f %f %f %f','HeaderLines',0,'CollectOutput',true);
    a=data{1}; clear closer;
    expectedN=121; if j==1 || j==8, expectedN=176; end
    assert(isequal(size(a),[expectedN 4]) && all(isfinite(a(:))), ...
        'Unexpected ngspice data shape/nonfinite data in %s',files{j});
    if j==1 || j==8
        targetVG=(0:0.02:3.5)'; vd=3; if j==8, vd=0.2; end
        assert(max(abs(a(:,1)-targetVG))<1e-8 && max(abs(a(:,2)-targetVG))<1e-8 ...
            && max(abs(a(:,3)-vd))<1e-8,'Transfer voltage grid mismatch.');
    else
        targetVD=(0:0.025:3)';
        assert(max(abs(a(:,1)-targetVD))<1e-8 && max(abs(a(:,3)-targetVD))<1e-8 ...
            && max(abs(a(:,2)-gates(j-1)))<1e-8,'Output voltage grid mismatch.');
    end
    model=mos_current(a(:,2),a(:,3),c); residual=a(:,4)-model;
    tol=c.spice_abs_tolerance_A+c.spice_rel_tolerance*abs(model);
    rows(j,:)=[j,size(a,1),max(abs(residual)),sqrt(mean(residual.^2)),all(abs(residual)<=tol)];
    write_csv(fullfile(outdir,sprintf('SPICE_comparison_%02d.csv',j)), ...
        {'sweep_V','VGS_V','VDS_V','I_SPICE_A','I_channel_model_A','residual_A','tolerance_A'}, ...
        [a model residual tol]);
    if j==1, transfer=[a model]; end
end
write_csv(fullfile(outdir,'SPICE_comparison_summary.csv'), ...
    {'case_id','points','max_abs_error_A','rmse_A','passed'},rows);
write_text(fullfile(outdir,'SPICE_CASE_NAMES.txt'),files(:));
end

function I=mos_current(vg,vd,c)
u=max(vg-c.vth_V,0); veff=min(vd,u);
I=c.beta_A_per_V2*(u.*veff-veff.^2/2).*(1+c.lambda_per_V*vd);
end
function [vth,coef]=threshold_fit(vgs,I,c)
mask=vgs>=c.fit_window_V(1)-1e-12 & vgs<=c.fit_window_V(2)+1e-12;
assert(nnz(mask)>=3 && all(isfinite(I(mask))) && all(I(mask)>0),'Invalid fit-window currents.');
coef=polyfit(vgs(mask),sqrt(I(mask)),1); assert(coef(1)>0,'Nonpositive slope.');
vth=-coef(2)/coef(1);
end
function out=new_folder(root)
base=fullfile(root,'outputs_stage2',datestr(now,'yyyymmdd_HHMMSS')); out=base; k=0;
while exist(out,'dir'), k=k+1; out=sprintf('%s_%03d',base,k); end
[ok,msg]=mkdir(out); assert(ok,'Cannot create output folder: %s',msg);
end
function write_csv(path,headers,data)
fid=fopen(path,'w'); assert(fid>=0,'Cannot write %s',path);
closer=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',strjoin(headers,','));
fmt=[repmat('%.17g,',1,size(data,2)-1) '%.17g\n']; fprintf(fid,fmt,data');
end
function write_text(path,lines)
fid=fopen(path,'w'); assert(fid>=0,'Cannot write %s',path);
closer=onCleanup(@() fclose(fid)); %#ok<NASGU>
for k=1:numel(lines), fprintf(fid,'%s\n',lines{k}); end
end
