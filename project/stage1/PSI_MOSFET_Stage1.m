function outdir = PSI_MOSFET_Stage1()
% PSI_MOSFET_Stage1  Synthetic MOSFET characterization learning project.
% Run: PSI_MOSFET_Stage1
% Base MATLAB; intended for R2019b or newer. No Simulink/toolboxes required.
% ALL currents are model-generated/synthetic. No hardware measurements.
% This is an educational DC square-law model, not a commercial device model.
% See ../../README_CN.md and ../../docs/RESULTS.md for results and scope.

cfg = configuration();
oldRng = rng; restoreRng = onCleanup(@() rng(oldRng)); %#ok<NASGU>
rng(cfg.seed, 'twister');
root = fileparts(mfilename('fullpath'));
outdir = new_output_folder(root);

fprintf('\n=== MOSFET STAGE 1: SYNTHETIC DATA ONLY ===\n');
fprintf('No experimental measurements; no SPICE run in this version.\n');
tests = self_checks(cfg, root);
fprintf('Numerical self-checks: %d/%d passed\n', sum(tests.pass), numel(tests.pass));
if ~all(tests.pass)
    error('PSI:SelfCheck', 'A self-check failed. Do not use these results.');
end

% 1. Ideal model curves. Gate and drain voltages are assumed exact.
vgs = cfg.vgs(:); vds = cfg.vds(:);
ideal = mos_current(vgs, cfg.vds_transfer, cfg);
output = zeros(numel(vds), numel(cfg.output_gates));
for j = 1:numel(cfg.output_gates)
    output(:,j) = mos_current(cfg.output_gates(j), vds, cfg);
end

% 2. Independent synthetic calibration and held-out check currents.
% Calibration references are assumed exact in this first teaching model.
[calSamples, nclipCal] = acquire(cfg.cal_refs, cfg.n_cal, ...
    cfg.demo_gain, cfg.demo_offset_A, cfg);
calMean = mean(calSamples, 2);
calCoef = polyfit(cfg.cal_refs, calMean, 1);
assert(calCoef(1) > 0, 'Calibration slope must be positive.');
[checkSamples, nclipCheck] = acquire(cfg.check_refs, cfg.n_avg, ...
    cfg.demo_gain, cfg.demo_offset_A, cfg);
checkMean = mean(checkSamples, 2);
checkCorrected = (checkMean - calCoef(2)) / calCoef(1);

% 3. A 25-reading mean at each gate voltage. Preserve signed readings.
[rawSamples, nclipSweep] = acquire(ideal, cfg.n_avg, ...
    cfg.demo_gain, cfg.demo_offset_A, cfg);
rawMean = mean(rawSamples, 2);
corrected = (rawMean - calCoef(2)) / calCoef(1);
[vthIdeal, ~, okIdeal] = threshold_fit(vgs, ideal, cfg);
[vthRaw, fitRaw, okRaw] = threshold_fit(vgs, rawMean, cfg);
[vthCal, fitCal, okCal] = threshold_fit(vgs, corrected, cfg);
assert(okIdeal && okRaw && okCal, 'Demo threshold fit invalid. Inspect data.');
% Numerical differentiation is deliberately unsmoothed; noise is not hidden.
gmIdeal = gradient(ideal, cfg.vgs_step);
gmRaw = gradient(rawMean, cfg.vgs_step);
gmCal = gradient(corrected, cfg.vgs_step);

% 4. Paired Monte Carlo: gain/offset held fixed WITHIN each scenario.
% Different scenarios sample a population of assumed instrument errors.
labels = {'Single raw', 'Mean25 raw', 'Single calibrated', 'Mean25 calibrated'};
mc = NaN(cfg.n_mc, 4); draws = zeros(cfg.n_mc, 2);
clipEvents = zeros(cfg.n_mc, 2);
for k = 1:cfg.n_mc
    gain = cfg.mc_gain_halfwidth * (2*rand-1);
    offset = cfg.mc_offset_halfwidth_A * (2*rand-1);
    draws(k,:) = [gain offset];
    [calK, clipEvents(k,1)] = acquire(cfg.cal_refs, cfg.n_cal, gain, offset, cfg);
    coefK = polyfit(cfg.cal_refs, mean(calK,2), 1);
    [readK, clipEvents(k,2)] = acquire(ideal, cfg.n_avg, gain, offset, cfg);
    if coefK(1) <= 0 || any(clipEvents(k,:) > 0)
        continue; % Keep failed scenario as NaN and report it; do not replace it.
    end
    singleK = readK(:,1); meanK = mean(readK,2);
    variants = [singleK, meanK, ...
        (singleK-coefK(2))/coefK(1), (meanK-coefK(2))/coefK(1)];
    for j = 1:4
        [estimate, ~, good] = threshold_fit(vgs, variants(:,j), cfg);
        if good, mc(k,j) = estimate; end
    end
end
% columns: valid, failed, bias, sd, rmse, p2.5, p97.5.
mcSummary = zeros(4,7);
for j = 1:4
    x = mc(isfinite(mc(:,j)),j);
    mcSummary(j,1:2) = [numel(x), cfg.n_mc-numel(x)];
    if isempty(x)
        mcSummary(j,3:7) = NaN;
    else
        mcSummary(j,3:7) = [mean(x)-cfg.vth_V, std(x,0), ...
            sqrt(mean((x-cfg.vth_V).^2)), empirical_quantile(x,0.025), ...
            empirical_quantile(x,0.975)];
    end
end

% Write numerical results before generating figures.
write_csv(fullfile(outdir,'transfer_SYNTHETIC.csv'), ...
    {'VGS_V','I_model_A','I_synthetic_raw_mean_A','I_synthetic_corrected_A', ...
     'gm_model_numeric_S','gm_synthetic_raw_S','gm_synthetic_corrected_S'}, ...
    [vgs ideal rawMean corrected gmIdeal gmRaw gmCal]);
headers = [{'VDS_V'}, arrayfun(@(x) sprintf('I_model_VGS_%.1fV_A',x), ...
    cfg.output_gates, 'UniformOutput',false)];
write_csv(fullfile(outdir,'output_MODEL.csv'), headers, [vds output]);
write_csv(fullfile(outdir,'raw_readings_SYNTHETIC.csv'), ...
    [{'VGS_V'}, arrayfun(@(x) sprintf('reading_%02d_A',x), ...
    1:cfg.n_avg,'UniformOutput',false)], [vgs rawSamples]);
write_csv(fullfile(outdir,'calibration_readings_SYNTHETIC.csv'), ...
    [{'exact_reference_A'}, arrayfun(@(x) sprintf('reading_%02d_A',x), ...
    1:cfg.n_cal,'UniformOutput',false)], [cfg.cal_refs calSamples]);
write_csv(fullfile(outdir,'heldout_readings_SYNTHETIC.csv'), ...
    [{'exact_reference_A'}, arrayfun(@(x) sprintf('reading_%02d_A',x), ...
    1:cfg.n_avg,'UniformOutput',false)], [cfg.check_refs checkSamples]);
write_csv(fullfile(outdir,'heldout_calibration_check_SYNTHETIC.csv'), ...
    {'exact_reference_A','raw_mean_A','corrected_A','raw_error_A','corrected_error_A'}, ...
    [cfg.check_refs checkMean checkCorrected ...
    checkMean-cfg.check_refs checkCorrected-cfg.check_refs]);
write_csv(fullfile(outdir,'monte_carlo_SYNTHETIC.csv'), ...
    {'scenario','drawn_gain_error','drawn_offset_A','Vth_single_raw_V', ...
     'Vth_mean25_raw_V','Vth_single_calibrated_V','Vth_mean25_calibrated_V', ...
     'clipped_calibration_readings','clipped_sweep_readings'}, ...
    [(1:cfg.n_mc)' draws mc clipEvents]);
write_csv(fullfile(outdir,'monte_carlo_summary_SYNTHETIC.csv'), ...
    {'method_id','valid','failed','bias_V','sd_V','rmse_V','p025_V','p975_V'}, ...
    [(1:4)' mcSummary]);
write_csv(fullfile(outdir,'self_checks.csv'), ...
    {'check_id','passed'},[(1:numel(tests.pass))' double(tests.pass(:))]);
copyfile(fullfile(root,'PSI_MOSFET_Stage1.m'),fullfile(outdir,'executed_source.m'));
fid = fopen(fullfile(outdir,'config.json'),'w');
assert(fid>=0,'Could not create config.json.');
fprintf(fid,'%s\n',jsonencode(cfg)); fclose(fid);
save(fullfile(outdir,'results.mat'),'cfg','tests','vgs','vds','ideal','output', ...
    'rawSamples','rawMean','corrected','calSamples','calCoef','checkSamples', ...
    'gmIdeal','gmRaw','gmCal','mc','mcSummary','draws','clipEvents','labels');

% Seven separate figures. A graphics failure does not erase numeric results.
plotError = '';
try
    f = figure('Name','01 Model output curves','NumberTitle','off');
    plot(vds,output*1e3,'LineWidth',1.3); grid on;
    xlabel('V_{DS} (V)'); ylabel('Model I_D (mA)');
    title('01 | Model output curves - not measurements');
    legend(arrayfun(@(x) sprintf('VGS = %.1f V',x),cfg.output_gates, ...
        'UniformOutput',false),'Location','northwest');
    save_plot(f,outdir,'01_output_MODEL');

    f = figure('Name','02 Synthetic transfer curves','NumberTitle','off');
    plot(vgs,ideal*1e3,'-',vgs,rawMean*1e3,'--',vgs,corrected*1e3,':','LineWidth',1.2);
    grid on; xlabel('V_{GS} (V)'); ylabel('I_D (mA)');
    title('02 | Transfer curve - synthetic measurement chain');
    legend('Ideal model','Raw mean of 25','Calibrated mean of 25','Location','northwest');
    save_plot(f,outdir,'02_transfer_SYNTHETIC');

    mask = fit_mask(vgs,cfg);
    f = figure('Name','03 Threshold extraction','NumberTitle','off');
    plot(vgs(mask),sqrt(rawMean(mask)),'o',vgs(mask),sqrt(corrected(mask)),'.'); hold on;
    xp = linspace(min([vthRaw vthCal cfg.vth_V])-0.03,cfg.fit_window_V(2),120);
    plot(xp,polyval(fitRaw,xp),'--',xp,polyval(fitCal,xp),'-');
    xline(cfg.vth_V,':','Model Vth'); yline(0,':'); grid on;
    xlabel('V_{GS} (V)'); ylabel('sqrt(I_D) (sqrt(A))');
    title('03 | Fixed-window sqrt-current fit - synthetic data');
    legend('Raw fit points','Corrected fit points','Raw extrapolation', ...
        'Corrected extrapolation','Location','northwest');
    save_plot(f,outdir,'03_threshold_fit_SYNTHETIC');

    f = figure('Name','04 Numerical transconductance','NumberTitle','off');
    plot(vgs,gmIdeal*1e3,'-',vgs,gmRaw*1e3,'--',vgs,gmCal*1e3,':','LineWidth',1.1);
    grid on; xlabel('V_{GS} (V)'); ylabel('Numerical g_m (mS)');
    title('04 | Unsmoothed derivative - synthetic data');
    legend('Ideal model','Raw mean25','Calibrated mean25','Location','northwest');
    save_plot(f,outdir,'04_gm_SYNTHETIC');

    f = figure('Name','05 Held-out calibration check','NumberTitle','off');
    plot(cfg.check_refs*1e3,(checkMean-cfg.check_refs)*1e6,'o-', ...
        cfg.check_refs*1e3,(checkCorrected-cfg.check_refs)*1e6,'s-');
    yline(0,':'); grid on; xlabel('Held-out exact reference current (mA)');
    ylabel('Synthetic current error (microampere)');
    title('05 | Separate held-out currents - no physical calibration');
    legend('Before correction','After correction','Location','best');
    save_plot(f,outdir,'05_heldout_check_SYNTHETIC');

    f = figure('Name','06 Scenario threshold distributions','NumberTitle','off');
    hold on;
    for j = 1:4
        values = sort(mc(isfinite(mc(:,j)),j)-cfg.vth_V)*1e3;
        if ~isempty(values)
            stairs(values,(1:numel(values))'/numel(values),'LineWidth',1.3);
        end
    end
    xline(0,':'); grid on; xlabel('Vth estimation error (mV)'); ylabel('Empirical cumulative fraction');
    title('06 | 400 assumed instrument scenarios - not real coverage');
    legend(labels,'Location','southeast');
    save_plot(f,outdir,'06_scenario_distribution_SYNTHETIC');

    f = figure('Name','07 Scenario RMSE comparison','NumberTitle','off');
    bar(mcSummary(:,5)*1e3); grid on;
    set(gca,'XTick',1:4,'XTickLabel',labels); xtickangle(15);
    ylabel('Vth RMSE across synthetic scenarios (mV)');
    title('07 | Averaging and calibration under stated assumptions');
    save_plot(f,outdir,'07_scenario_rmse_SYNTHETIC');
catch ME
    plotError = ME.message;
    warning('PSI:Graphics','Numerical results saved; graphics incomplete: %s',ME.message);
end

lines = {'MOSFET STAGE 1 - SYNTHETIC DATA ONLY'; ...
    ['MATLAB: ' version]; ...
    sprintf('Seed: %d; Monte Carlo scenarios: %d',cfg.seed,cfg.n_mc); ...
    sprintf('Numerical checks: %d/%d passed',sum(tests.pass),numel(tests.pass)); ...
    sprintf('Vth model parameter = %.9f V',cfg.vth_V); ...
    sprintf('Vth noiseless fit    = %.9f V',vthIdeal); ...
    sprintf('Vth raw mean25       = %.9f V',vthRaw); ...
    sprintf('Vth corrected mean25 = %.9f V',vthCal); ...
    sprintf('Synthetic calibration slope = %.9f; intercept = %.9g A',calCoef(1),calCoef(2)); ...
    sprintf('Clipped demo samples = %d',nclipCal+nclipCheck+nclipSweep); ...
    sprintf('MC scenarios with clipped samples = %d',sum(any(clipEvents>0,2))); ...
    'MC rows: method | valid | failed | bias_mV | sd_mV | rmse_mV | p025_V | p975_V'};
for j = 1:4
    lines{end+1,1} = sprintf('%s | %d | %d | %.6f | %.6f | %.6f | %.9f | %.9f', ...
        labels{j},mcSummary(j,1:2),mcSummary(j,3:5)*1e3,mcSummary(j,6:7)); %#ok<AGROW>
end
lines = [lines; {'Percentiles describe simulated estimator distributions, not validated confidence intervals.'; ...
    'No temperature, gate/drain voltage uncertainty, drift, 1/f noise, loading or self-heating model.'; ...
    'Reference currents are assumed exact. This is not traceable physical calibration.'; ...
    'No hardware, wafer probing, commercial-device validation or SPICE run has been completed here.'; ...
    ['Graphics error (blank means none): ' plotError]; ...
    ['Results folder: ' outdir]}];
write_lines(fullfile(outdir,'SUMMARY.txt'),lines);
write_lines(fullfile(outdir,'SELF_CHECK_NAMES.txt'),tests.names(:));
for k = 1:numel(lines), fprintf('%s\n',lines{k}); end
end

function c = configuration()
% Educational assumptions; NOT component specifications or measured values.
c.version = '1.0'; c.data_origin = 'SYNTHETIC_MODEL_NOT_EXPERIMENT';
c.seed = 20260920;
c.vth_V = 1.2; c.beta_A_per_V2 = 0.002; c.lambda_per_V = 0.02;
c.vgs_step = 0.02; c.vgs = (0:0.02:3.5)'; c.vds = (0:0.025:3)';
c.vds_transfer = 3.0; c.output_gates = [1.0 1.5 2.0 2.5 3.0 3.5];
c.fit_window_V = [1.7 2.7]; % Preset, not optimized after seeing outcomes.
c.adc_bits = 12; c.adc_positive_fullscale_A = 0.010;
c.noise_sd_A = 4e-6; c.n_avg = 25; c.n_cal = 32;
c.demo_gain = 0.008; c.demo_offset_A = 15e-6;
c.cal_refs = [0;0.006]; c.check_refs = [0.001;0.003;0.005];
c.n_mc = 400; c.mc_gain_halfwidth = 0.010; c.mc_offset_halfwidth_A = 20e-6;
assert(c.beta_A_per_V2>0 && c.lambda_per_V>=0 && c.vth_V>0);
assert(c.adc_bits==floor(c.adc_bits) && c.adc_bits>=2 && c.adc_bits<=24);
assert(c.noise_sd_A>=0 && c.n_avg>=1 && c.n_cal>=2 && c.n_mc>=2);
assert(c.fit_window_V(1)>c.vth_V && ...
    c.fit_window_V(2)-c.vth_V<c.vds_transfer, 'Fit window must be on and saturated.');
end

function I = mos_current(vg,vd,c)
% DC long-channel square-law channel current. VSB=0; forward operation only.
assert(all(isfinite(vg(:))) && all(isfinite(vd(:))) && all(vd(:)>=0));
u = vg-c.vth_V + zeros(size(vd)); d = vd+zeros(size(vg));
I = zeros(size(u));
tri = u>0 & d<u; sat = u>0 & d>=u;
I(tri) = c.beta_A_per_V2*(u(tri).*d(tri)-0.5*d(tri).^2) ...
    .*(1+c.lambda_per_V*d(tri));
I(sat) = 0.5*c.beta_A_per_V2*u(sat).^2.*(1+c.lambda_per_V*d(sat));
end

function [q,nclip] = quantize_current(x,c)
% Signed ideal ADC: codes -2^(B-1) ... 2^(B-1)-1; LSB=2*FS/2^B.
lsb = 2*c.adc_positive_fullscale_A/(2^c.adc_bits);
code = round(x/lsb); lo = -2^(c.adc_bits-1); hi = 2^(c.adc_bits-1)-1;
nclip = nnz(code<lo | code>hi);
q = min(max(code,lo),hi)*lsb;
end

function [samples,nclip] = acquire(truth,n,gain,offset,c)
x = repmat((1+gain)*truth(:)+offset,1,n) ...
    +c.noise_sd_A*randn(numel(truth),n);
[samples,nclip] = quantize_current(x,c);
end

function mask = fit_mask(vgs,c)
mask = vgs>=c.fit_window_V(1)-1e-12 & vgs<=c.fit_window_V(2)+1e-12;
end

function [vth,coef,ok] = threshold_fit(vgs,current,c)
vth = NaN; coef = [NaN NaN]; ok = false;
mask = fit_mask(vgs,c); y = current(mask); x = vgs(mask);
% Reject, never turn negative current into zero just to take sqrt().
if numel(y)<3 || any(~isfinite(y)) || any(y<=0), return; end
coef = polyfit(x,sqrt(y),1);
if ~all(isfinite(coef)) || coef(1)<=0, return; end
vth = -coef(2)/coef(1); ok = isfinite(vth);
end

function q = empirical_quantile(x,p)
x = sort(x(:)); h = 1+(numel(x)-1)*p; a = floor(h); b = ceil(h);
q = x(a)+(h-a)*(x(b)-x(a));
end

function t = self_checks(c,root)
t.names = {}; t.pass = [];
    function add(name,passed)
        t.names{end+1,1}=name; t.pass(end+1,1)=logical(passed);
    end
add('Below-threshold channel current is zero',all(mos_current([0;0.6;1.2],3,c)==0));
add('Zero drain bias gives zero channel current',all(mos_current([1.4;2;3],0,c)==0));
x = mos_current(c.vgs,3,c);
add('Transfer curve is nonnegative and monotone',all(x>=0) && all(diff(x)>=-1e-14));
add('Output curves are nonnegative and monotone',all(all(diff(mos_current(c.output_gates,c.vds,c),1,1)>=-1e-14)));
vg = 2.2; boundary = vg-c.vth_V; epsilon = 1e-8;
add('Continuity at triode-saturation boundary', ...
    abs(mos_current(vg,boundary-epsilon,c)-mos_current(vg,boundary+epsilon,c))<1e-10);
h = 1e-5; numeric = (mos_current(2+h,3,c)-mos_current(2-h,3,c))/(2*h);
analytic = c.beta_A_per_V2*(2-c.vth_V)*(1+3*c.lambda_per_V);
add('Finite-difference gm agrees with analytic saturated gm',abs(numeric-analytic)<1e-10);
[v,~,ok] = threshold_fit(c.vgs,x,c);
add('Noiseless Vth extraction recovers known model parameter',ok && abs(v-c.vth_V)<1e-10);
[q,nclip] = quantize_current([-1;0;1]*c.adc_positive_fullscale_A*2,c);
add('ADC clipping is detected and output is bounded',nclip==2 && ...
    min(q)>=-c.adc_positive_fullscale_A && max(q)<c.adc_positive_fullscale_A);
[q,~] = quantize_current(-10e-6,c);
add('Signed negative synthetic readings are preserved',q<0);
r = c.cal_refs; p = polyfit(r,1.008*r+15e-6,1);
add('Exact affine inverse correction recovers reference currents',max(abs(((1.008*r+15e-6)-p(2))/p(1)-r))<1e-12);
x(fit_mask(c.vgs,c)) = -1;
[~,~,ok] = threshold_fit(c.vgs,x,c);
add('Nonpositive fit-window currents are rejected',~ok);
fp = fullfile(root,'verification','ideal_reference_vectors.csv');
if exist(fp,'file')
    ref = dlmread(fp,',',1,0);
    val = mos_current(ref(:,1),ref(:,2),c);
    add('Deterministic currents agree with packaged Python reference',max(abs(val-ref(:,3)))<1e-12);
end
end

function out = new_output_folder(root)
base = fullfile(root,'outputs',datestr(now,'yyyymmdd_HHMMSS')); out = base; k=0;
while exist(out,'dir'), k=k+1; out=sprintf('%s_%03d',base,k); end
[ok,msg] = mkdir(out); assert(ok,'Cannot create output folder: %s',msg);
end

function write_csv(path,headers,data)
fid = fopen(path,'w'); assert(fid>=0,'Cannot create %s',path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',strjoin(headers,','));
fmt = [repmat('%.15g,',1,size(data,2)-1) '%.15g\n'];
fprintf(fid,fmt,data');
end

function write_lines(path,lines)
fid = fopen(path,'w'); assert(fid>=0,'Cannot create %s',path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
for k = 1:numel(lines), fprintf(fid,'%s\n',lines{k}); end
end

function save_plot(f,outdir,name)
saveas(f,fullfile(outdir,[name '.png']));
end
