%% ENROLL_STUDENTS - Build enrollment, Factor 1 verifier, and Factor 2 digit-only model
% Run THIS script after adding/changing prerecorded student WAV files, or
% when the persistent models are missing/incompatible. RUN_ME.m does not
% enroll students or train models.
%
% Expected sibling folders:
%   raw_records/             source recordings (never modified here)
%   database/                stores EnrolledDatabase.mat, VerifierModel.mat, DigitVoiceModel.mat
%   ParkingSecuritySystem/   this script and the verification code

%% ======================== SETTINGS ================================
FORCE_REBUILD = false;  % true: always re-enroll AND retrain from raw_records
SHOW_TRAINING_PLOTS = true;  % figures from verifier-training evaluation
%% ==================================================================

clc; close all;
codeDir = fileparts(mfilename('fullpath'));
addpath(codeDir);
cfg = vsConfig();

fprintf('=======================================================\n');
fprintf('    ANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE  -  OFFLINE ENROLLMENT\n');
fprintf('    recordings: %s\n', cfg.RawRecordsDir);
fprintf('    models    : %s\n', cfg.DataDir);
fprintf('=======================================================\n');

if ~isfolder(cfg.RawRecordsDir)
    error('ParkingSecuritySystem:MissingRawRecords', ...
          'Cannot enroll: raw_records/ not found beside ParkingSecuritySystem/: %s', ...
          cfg.RawRecordsDir);
end

% Prevent accidentally discarding previously trained models left in an old
% code/data/ directory. The new persistent location is sibling database/.
if ~FORCE_REBUILD
    oldDirs = {fullfile(cfg.CodeDir, 'data'), fullfile(cfg.ProjectDir, 'data')};
    names = {'EnrolledDatabase.mat', 'VerifierModel.mat'};
    for d = 1:numel(oldDirs)
        for k = 1:numel(names)
            newFile = fullfile(cfg.DataDir, names{k});
            oldFile = fullfile(oldDirs{d}, names{k});
            if ~isfile(newFile) && isfile(oldFile)
                error('ParkingSecuritySystem:MoveExistingModels', ...
                      ['Found a model in the OLD folder:\n  %s\n' ...
                       'Move BOTH existing MAT files into:\n  %s\n' ...
                       'or set FORCE_REBUILD = true to rebuild intentionally.'], ...
                      oldFile, cfg.DataDir);
            end
        end
    end
end
if ~isfolder(cfg.DataDir), mkdir(cfg.DataDir); end

% Re-enroll when explicitly requested, no database exists, source recordings
% changed, or the recorded feature/database format is no longer compatible.
needEnroll = FORCE_REBUILD || ~isfile(cfg.DatabaseFile);
if ~needEnroll
    try
        s = load(cfg.DatabaseFile, 'DatabaseVersion', 'ConfigUsed', 'Students', 'UBM');
        needEnroll = ~isfield(s, 'DatabaseVersion') || s.DatabaseVersion < 6 || ...
                     ~isfield(s, 'ConfigUsed') || ...
                     ~isfield(s.ConfigUsed, 'PipelineVersion') || ...
                     ~strcmp(s.ConfigUsed.PipelineVersion, cfg.PipelineVersion) || ...
                     ~isfield(s, 'Students') || isempty(s.Students) || ...
                     ~isfield(s.Students, 'Digits') || ~isfield(s, 'UBM');
    catch
        fprintf('[WARNING] Existing enrollment MAT could not be read; rebuilding.\n');
        needEnroll = true;
    end
end
if ~needEnroll
    needEnroll = newestRecording(cfg.RawRecordsDir) > fileTime(cfg.DatabaseFile);
end

if needEnroll
    fprintf('\n[ENROLL 1/3] Building enrollment models from raw_records/ ...\n');
    ParkingSecuritySystem('enroll');
else
    fprintf('\n[ENROLL 1/3] Enrollment database is up to date; keeping existing MAT file.\n');
end

% A trained verifier belongs to a particular enrollment DB. Rebuild its
% thresholds whenever that database changes or its saved model is invalid.
needTrain = needEnroll || ~isfile(cfg.VerifierModelFile) || ...
            fileTime(cfg.VerifierModelFile) < fileTime(cfg.DatabaseFile);
if ~needTrain
    try
        checkModelsReady(cfg);
    catch ME
        fprintf('[WARNING] Saved verifier failed the compatibility check: %s\n', ME.message);
        needTrain = true;
    end
end

if needTrain
    fprintf('\n[ENROLL 2/3] Training and evaluating the verifier ...\n');
    trainVerifier(SHOW_TRAINING_PLOTS);
else
    fprintf('[ENROLL 2/3] Trained verifier is up to date; keeping existing MAT file.\n');
end

% Separate Factor 2 GMM-UBM training. Never rebuild valid Factor 1 models
% merely because this dedicated, independent digit-only model is missing.
needDigitVoice = needEnroll || ~isfile(cfg.DigitVoiceModelFile) || ...
                 fileTime(cfg.DigitVoiceModelFile) < fileTime(cfg.DatabaseFile);
if ~needDigitVoice
    try
        checkDigitVoiceReady(cfg);
    catch ME
        fprintf('[WARNING] Digit-only model needs rebuilding: %s\n',ME.message);
        needDigitVoice = true;
    end
end
if needDigitVoice
    fprintf('\n[ENROLL 3/3] Training the separate digit-only speaker model ...\n');
    trainDigitVoiceModel(cfg);
else
    fprintf('[FACTOR 2] Digit-only speaker model is up to date.\n');
end

% Final checks; RUN_ME never enrolls or repairs missing files.
checkModelsReady(cfg);
checkDigitVoiceReady(cfg);
ParkingSecuritySystem('status');
fprintf('\nENROLLMENT COMPLETE. Run RUN_ME.m for LIVE verification.\n');

%% Local helpers
function t = newestRecording(dirName)
f = [dir(fullfile(dirName, '**', '*.wav')); ...
     dir(fullfile(dirName, '**', '*.m4a')); ...
     dir(fullfile(dirName, 'speakers.csv'))];
if isempty(f), t = 0; else, t = max([f.datenum]); end
end

function t = fileTime(fileName)
f = dir(fileName);
if isempty(f), t = 0; else, t = f.datenum; end
end
