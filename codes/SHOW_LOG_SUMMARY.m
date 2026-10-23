%% SHOW_LOG_SUMMARY - Results across completed LIVE GUI and command sessions.
% Only local metadata is read. Offline tests and enrollment are not counted.
cfg = vsConfig();
csvPath = fullfile(cfg.ProjectDir,'verification_logs','verification_history.csv');
if ~isfile(csvPath)
    fprintf('No saved verification sessions yet. Run RUN_ME and verify first.\n');
else
    T = readtable(csvPath,'TextType','string');
    n = height(T);
    granted = sum(strcmp(T.Decision,'GRANTED'));
    denied = sum(strcmp(T.Decision,'DENIED'));
    errors = sum(strcmp(T.Decision,'ERROR'));
    f1Passed = sum(strcmp(T.Factor1Status,'PASSED'));
    f1Failed = sum(strcmp(T.Factor1Status,'FAILED'));
    f2Passed = sum(strcmp(T.Factor2Status,'PASSED'));
    f2Failed = sum(strcmp(T.Factor2Status,'FAILED'));
    fprintf('\n=========== VERIFICATION LOG SUMMARY ===========\n');
    fprintf('Logged sessions            : %d\n', n);
    fprintf('Access granted             : %d\n', granted);
    fprintf('Access denied              : %d\n', denied);
    fprintf('Session errors             : %d\n', errors);
    fprintf('Factor 1 passed / failed   : %d / %d\n', f1Passed, f1Failed);
    fprintf('Factor 2 passed / failed   : %d / %d\n', f2Passed, f2Failed);
    fprintf('Factor 2 not attempted     : %d\n', sum(strcmp(T.Factor2Status,'NOT_RUN')));
    fprintf('===============================================\n');
    fprintf('Detailed CSV: %s\n', csvPath);
end
