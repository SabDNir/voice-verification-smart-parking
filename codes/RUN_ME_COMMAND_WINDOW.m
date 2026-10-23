%% RUN_ME_COMMAND_WINDOW - Interactive verification ONLY (no enrollment or model training)
% Required sibling folders:
%   raw_records/             prerecorded enrollment audio (not changed here)
%   database/                persistent EnrolledDatabase.mat, VerifierModel.mat and DigitVoiceModel.mat
%   ParkingSecuritySystem/   MATLAB code, including RUN_ME.m
%
% To add students, refresh recordings or rebuild models, run
% ENROLL_STUDENTS.m SEPARATELY. RUN_ME never modifies either MAT file.

clc; close all;
codeDir = fileparts(mfilename('fullpath'));
addpath(codeDir);
cfg = vsConfig();

fprintf('=======================================================\n');
fprintf('    ANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE  -  LIVE VERIFICATION\n');
fprintf('    code       : %s\n', codeDir);
fprintf('    raw records: %s\n', cfg.RawRecordsDir);
fprintf('    models     : %s\n', cfg.DataDir);
fprintf('=======================================================\n');

% Check saved models BEFORE activating the microphone. There is deliberately
% no enrollment/training fallback in this live-verification entry point.
checkModelsReady(cfg);
checkDigitVoiceReady(cfg); % fail before microphone, never auto-train
ParkingSecuritySystem('status');

fprintf('\nReady. Remain SILENT for the initial 3-second ambient recording.\n');
fprintf('Enter your ID at the prompt, then say roll + name.\n');
fprintf('Only a matching Factor 1 identity proceeds to the fresh three-digit code.\n');
fprintf('Verification recordings stay in RAM and are not saved.\n');

while true
    [ok, id, rep] = ParkingSecuritySystem('verify'); %#ok<ASGLU>
    if ok
        fprintf('\nRESULT: ACCESS GRANTED  (%s)\n', id);
    else
        fprintf('\nRESULT: ACCESS DENIED   (%s)\n', rep.Reason);
    end
    answer = questdlg('Verify another student?', 'Anti-Theft System for Smart Parking Infrastructure', ...
                      'Verify again', 'Stop', 'Verify again');
    if ~strcmp(answer, 'Verify again'), break; end
    close all;
end
