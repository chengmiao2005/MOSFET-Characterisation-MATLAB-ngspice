function outdir = RUN_STAGE2B(spiceExe)
% RUN_STAGE2B  Require a SPICE engine; run the unchanged Stage 2 code.
% Open this file in MATLAB and press Run, or enter: RUN_STAGE2B
% Optional explicit path: RUN_STAGE2B('D:\Spice64\bin\ngspice_con.exe')
% This launcher does not download software, edit models, or relax tolerances.
% Cancellation stops before any simulation. A returned folder is not a PASS.

outdir = '';
root = fileparts(mfilename('fullpath'));
required = {'PSI_MOSFET_Stage2.m', ...
    fullfile('spice_case','mosfet_level1.cir'), ...
    fullfile('verification','mechanism_reference_MODEL.csv'), ...
    fullfile('verification','low_vds_fit_reference_MODEL.csv')};
for k = 1:numel(required)
    assert(exist(fullfile(root,required{k}),'file') == 2, ...
        'PSI:MissingFile','Missing %s. Extract the ENTIRE project ZIP first.',required{k});
end

fprintf('\nSTAGE 2B: select the ngspice executable, NOT a .cir/.m/.7z file.\n');
fprintf('No engine selected = stop; no silent fallback to Stage 2A.\n');
if nargin < 1 || isempty(spiceExe)
    if ispc
        filter = {'*.exe','ngspice executable (*.exe)'; '*.*','All files'};
    else
        filter = {'*','ngspice executable'};
    end
    [f,p] = uigetfile(filter,'Select ngspice_con.exe (inside Spice64/bin)');
    if isequal(f,0)
        fprintf(2,'STOPPED: no engine selected; no simulation was started.\n');
        fprintf(2,'Install/extract ngspice if needed, then run RUN_STAGE2B again.\n');
        return;
    end
    spiceExe = fullfile(p,f);
end
if isstring(spiceExe) && isscalar(spiceExe), spiceExe = char(spiceExe); end
assert(ischar(spiceExe) && isrow(spiceExe) && ~isempty(spiceExe), ...
    'PSI:EnginePath','Provide one full executable path.');
assert(exist(spiceExe,'file') == 2,'PSI:EngineMissing','Executable not found: %s',spiceExe);
if ispc
    [~,name,extension] = fileparts(spiceExe);
    assert(any(strcmpi([name extension],{'ngspice_con.exe','ngspice.exe'})), ...
        'PSI:WrongProgram','Select ngspice_con.exe or ngspice.exe, not another application.');
end

previous = pwd;
restoreDirectory = onCleanup(@() cd(previous)); %#ok<NASGU>
cd(root);
resolved = which('PSI_MOSFET_Stage2');
assert(strcmpi(resolved,fullfile(root,'PSI_MOSFET_Stage2.m')), ...
    'PSI:WrongSource','Another Stage 2 copy is selected on the MATLAB path.');
fprintf('Selected engine: %s\n',spiceExe);
% The original code records actual execution status and preserves failed runs.
outdir = PSI_MOSFET_Stage2(spiceExe);
copyfile(fullfile(root,'RUN_STAGE2B.m'),fullfile(outdir,'executed_launcher.m'));
statusText = fileread(fullfile(outdir,'STATUS.txt'));
fprintf('\n========== ACTUAL SAVED STATUS ==========\n%s\n',statusText);
if contains(statusText,'SPICE_STATUS=EXECUTED_COMPARISON_PASS')
    fprintf('Shared-model numerical comparison PASSED. Not hardware validation.\n');
else
    fprintf(2,'SPICE comparison has NOT passed. Keep every log; do not change tolerances.\n');
end

% Package THIS run only, including the entire spice_case subfolder and logs.
[parent,leaf] = fileparts(outdir);
archive = fullfile(root,['Stage2B_result_' leaf '.zip']);
try
    zip(archive,{leaf},parent);
    fprintf('\nUPLOAD THIS FILE (including failed comparison runs):\n%s\n',archive);
catch ME
    warning('PSI:ArchiveFailed','Automatic ZIP failed: %s',ME.message);
    fprintf('Please zip this entire results folder manually:\n%s\n',outdir);
end
end
