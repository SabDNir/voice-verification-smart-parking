function app = runProject()
%RUNPROJECT Launch Group 04's original visual GUI with the project backend.
% This never builds/changes a model. Use ENROLL_STUDENTS.m separately.
codeDir=fileparts(mfilename('fullpath'));
addpath(codeDir,'-begin');
cfg=vsConfig();
fprintf('\n=======================================================\n');
fprintf('   ANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE - LIVE VERIFICATION\n');
fprintf('   source WAVs: %s\n',cfg.RawRecordsDir);
fprintf('   model files: %s\n',cfg.DataDir);
fprintf('=======================================================\n');
checkModelsReady(cfg);
model=checkDigitVoiceReady(cfg);
s=load(cfg.DatabaseFile,'Students');
fprintf('   Enrolled speakers (Factor 1): %d\n',numel(s.Students));
fprintf('   Digit-speaker eligible (Factor 2): %d\n',numel(model.Rolls));
ParkingSecuritySystem('status');
fprintf('\nStart a session by entering the claimed ID in the GUI.\n');
fprintf('Detailed verification reports will appear here.\n');
app=ParkingSecuritySystemApp();
if nargout==0
    assignin('base','parkingApp',app);
end
end
