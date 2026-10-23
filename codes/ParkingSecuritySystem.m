function varargout = ParkingSecuritySystem(action, varargin)
%PARKINGSECURITYSYSTEM  Two-factor roll/name and fresh three-digit login.
%
% Prefer ENROLL_STUDENTS.m for safe offline enrollment/retraining.
% ParkingSecuritySystem('enroll')
% ParkingSecuritySystem('train')
% ParkingSecuritySystem('status')
% [ok, roll, report] = ParkingSecuritySystem('verify')
% [ok, roll, report] = ParkingSecuritySystem('verifyfiles', ...
%                            rollWav, nameWav, challengeWav, [d1 d2 d3], enteredID)
% Offline diagnostic allows omitted enteredID for previous test scripts.
%
% Factor 1 UNCHANGED: roll+name DTW/cohort plus four GMM-UBM voice gates.
% Factor 2 NEW: random 0..9 three-digit challenge. ALL digit-content tests
% and BOTH same-speaker GMM-UBM checks are mandatory. A Factor 1 pass NEVER
% grants access by itself. No replay classifier or captured WAV file output.

if nargin < 1, action = 'help'; end
cfg = vsConfig();
if ~exist(cfg.DataDir, 'dir'), mkdir(cfg.DataDir); end

switch lower(char(action))
    case {'help', '-h', '--help'}
        vsIO('help');
        varargout = {};
    case 'status'
        vsIO('status');
        varargout = {};
    case 'enroll'
        folder = vsIO('getarg', varargin, 1, cfg.RawRecordsDir);
        result = enrollTemplates(folder, cfg.DatabaseFile);
        varargout = vsIO('packout', {result}, nargout);
    case 'train'
        result = trainVerifier(true);
        varargout = vsIO('packout', {result}, nargout);
    case 'verify'
        checkModelsReady(cfg); % Fail before recording anything if setup is missing.
        checkDigitVoiceReady(cfg);
        try
            [ok, id, report] = verifyLive(cfg);
        catch ME
            saveVerificationLog(false, 'REJECTED', ...
                struct('Reason', ME.message, 'Stage', 'error'), '', 'COMMAND', cfg);
            rethrow(ME);
        end
        saveVerificationLog(ok, id, report, '', 'COMMAND', cfg);
        varargout = vsIO('packout', {ok, id, report}, nargout);
    case 'verifygui'
        % SAME live engine, same enrollment/models/thresholds/mic capture.
        % GUI only supplies the typed ID and receives read-only event updates.
        if numel(varargin) ~= 2 || ~isstruct(varargin{2})
            error('ParkingSecuritySystem:GUIUsage', ...
                'Usage: ParkingSecuritySystem(''verifygui'', enteredID, callbackStruct).');
        end
        checkModelsReady(cfg);
        checkDigitVoiceReady(cfg);
        cfg.DisableVerificationPlot = true; % GUI already has waveform/spectrum panes.
        claimedID = char(string(varargin{1}));
        try
            [ok, id, report] = verifyLive(cfg, claimedID, varargin{2});
        catch ME
            saveVerificationLog(false, 'REJECTED', ...
                struct('Reason', ME.message, 'Stage', 'error'), claimedID, 'GUI', cfg);
            rethrow(ME);
        end
        saveVerificationLog(ok, id, report, claimedID, 'GUI', cfg);
        varargout = vsIO('packout', {ok, id, report}, nargout);
    case 'verifyfiles'
        % Offline regression testing ONLY. The explicit expected digits are
        % trusted by this test command, not by the live access flow.
        if ~ismember(numel(varargin), [4 5])
            error('ParkingSecuritySystem:Usage', ...
                  ['Usage: ParkingSecuritySystem(''verifyfiles'', ' ...
                   'rollWav, nameWav, challengeWav, [d1 d2 d3], [enteredID]). ' ...
                   'Two files cannot produce an access-granted result.']);
        end
        checkModelsReady(cfg);
        checkDigitVoiceReady(cfg);
        [a, fs1] = audioread(char(varargin{1}));
        [b, fs2] = audioread(char(varargin{2}));
        [c, fs3] = audioread(char(varargin{3}));
        expected = double(varargin{4});
        enteredID = '';
        if numel(varargin) == 5
            enteredID = strtrim(char(string(varargin{5})));
            validateEnteredID(enteredID, loadDatabase(cfg));
        end
        [ok, id, report] = verifyFromFiles({a, b, c}, [fs1, fs2, fs3], expected, enteredID, cfg);
        varargout = vsIO('packout', {ok, id, report}, nargout);
    otherwise
        error('ParkingSecuritySystem:Action', 'Unknown action: %s', char(action));
end
end


function [ok, id, report] = verifyLive(cfg, suppliedID, guiHooks)
% A FAILED challenge rejects this login even when Factor 1 was successful.
% Empty suppliedID = original interactive Command Window entry mode.
% Nonempty suppliedID = exact user-typed GUI identity (never auto-inferred).
guiMode = nargin >= 3;
if nargin < 2, suppliedID = ''; end
if nargin < 3, guiHooks = struct(); end
ok = false;
id = 'REJECTED';
report = struct('Reason', 'Speech not captured.', 'Stage', 'factor1');
% Entry is a claimed identity, never evidence of speaker/content correctness.
% Validate before microphone capture, then bind the session to the entered ID.
dbForClaim = loadDatabase(cfg);
fprintf('\n');
if ~guiMode
    enteredID = strtrim(input('ENTER YOUR STUDENT ID: ', 's'));
else
    enteredID = strtrim(suppliedID);
    fprintf('ENTER YOUR STUDENT ID: %s\n', enteredID);
end
report.EnteredID = enteredID; % metadata only, for the local verification log
try
    validateEnteredID(enteredID, dbForClaim);
catch ME
    report.Reason = ME.message;
    report.Stage = 'claim';
    fprintf('ACCESS DENIED: %s\n', report.Reason);
    notifyGUI(guiHooks, 'OnNotice', 'claim', report.Reason);
    return;
end
digitReady = checkDigitVoiceReady(cfg, dbForClaim);
if ~any(strcmp(digitReady.Rolls, enteredID))
    report.Reason = 'This ID lacks 10 usable isolated digits for the dedicated Factor 2 speaker model. Add the recordings and run ENROLL_STUDENTS.m.';
    report.Stage = 'claim';
    fprintf('ACCESS DENIED: %s\n', report.Reason);
    notifyGUI(guiHooks, 'OnNotice', 'claim', report.Reason);
    return;
end
fprintf('[CLAIM] Entered ID: %s. Factor 1 must independently authenticate this same ID.\n', enteredID);
% Acquire one fixed 3-second noise reference BEFORE any login speech. The
% runtime-only profile is reused for ALL Factor 1 attempts and the Factor 2
% challenge. An invalid reference falls back to the original per-utterance
% quiet-frame estimator without requiring another microphone recording.
if cfg.UseAmbientNoiseReference && cfg.SpectralSubtraction
    notifyGUI(guiHooks, 'OnPrompt', 'noise', []);
    [ambient, ambientFs, ambientInfo] = vsIO('recordnoise');
    notifyGUI(guiHooks, 'OnAudio', 'noise', ambient, ambientFs);
    if ambientInfo.Valid
        [profile, problem] = buildAmbientNoiseProfile(ambient, ambientFs, cfg);
        if ~isempty(profile)
            cfg.AmbientNoiseProfile = profile;
            fprintf('[AMBIENT] VALID: %.1f s; level %.1f dBFS.\n', ...
                    profile.Seconds, profile.NoiseDbFS);
            fprintf('[AMBIENT] Shared profile will be used for roll, name and challenge.\n');
        else
            fprintf('[AMBIENT] Invalid reference: %s\n', problem);
            fprintf('[AMBIENT] FALLBACK: per-utterance quiet-frame estimation.\n');
        end
    else
        fprintf('[AMBIENT] Invalid reference: %s\n', ambientInfo.Reason);
        fprintf('[AMBIENT] FALLBACK: per-utterance quiet-frame estimation.\n');
    end
    clear ambient   % never save or retain the raw reference recording
elseif cfg.SpectralSubtraction
    fprintf('[AMBIENT] 3-second reference disabled; using per-utterance quiet-frame estimator.\n');
end
% MATLAB's default pseudorandom seed may repeat after a fresh launch. Shuffle
% once per live verification session so challenges vary between launches.
rng('shuffle');
prompts = {'Say your roll number', 'Say your full name'};

for attempt = 1:cfg.MaxAuthAttempts
    if attempt > 1, fprintf('\n[RETRY] Please repeat roll number AND full name.\n'); end
    audios = cell(1, 2);
    fss = zeros(1, 2);
    good = true;
    for k = 1:2
        notifyGUI(guiHooks, 'OnPrompt', cfg.LoginSequence{k}, []);
        [audios{k}, fss(k), info] = vsIO('record', prompts{k});
        notifyGUI(guiHooks, 'OnAudio', cfg.LoginSequence{k}, audios{k}, fss(k));
        if ~info.SpeechFound
            report = struct('Reason', sprintf('No speech detected: %s.', cfg.LoginSequence{k}), ...
                            'Stage', 'factor1', 'EnteredID', enteredID);
            fprintf('[CAPTURE] %s\n', report.Reason);
            good = false;
            break;
        end
    end
    if ~good, continue; end

    [factor1, candidate, f1report, db] = runFactor1(audios, fss, cfg);
    notifyGUI(guiHooks, 'OnFactor1', factor1 && strcmp(candidate, enteredID), ...
              candidate, f1report, enteredID);
    report = struct('Reason', f1report.Reason, 'Stage', 'factor1', ...
                    'EnteredID', enteredID, 'Factor1', f1report, 'Factor2', []);
    if factor1 && ~strcmp(candidate, enteredID)
        report.Reason = sprintf(['Entered ID %s does not match the independently ' ...
            'verified Factor 1 identity.'], enteredID);
        fprintf('[CLAIM MISMATCH] Access denied: entered ID and verified identity differ.\n');
        fprintf('ACCESS DENIED: %s\n', report.Reason);
        return; % Never issue a challenge for the wrong claimed identity.
    end
    if factor1
        % Only now reveal a random, newly generated challenge. The user can
        % neither choose it nor reuse any digits entered in Factor 1.
        for cAttempt = 1:cfg.MaxChallengeAttempts
            expected = randi([0, 9], 1, cfg.ChallengeLength);
            notifyGUI(guiHooks, 'OnChallenge', expected);
            fprintf('\n=======================================================\n');
            fprintf('FACTOR 1 PASSED  ->  %s\n', candidate);
            fprintf('FRESH %d-DIGIT CHALLENGE:  %s\n', cfg.ChallengeLength, ...
                    strtrim(sprintf('%d ', expected)));
            fprintf('Speak digits separately with %.2f-%.2f s pauses (below %.1f s).\n', ...
                    cfg.ChallengePauseLowSec,cfg.ChallengePauseHighSec,cfg.EndSilenceSeconds);
            fprintf('=======================================================\n');
            notifyGUI(guiHooks, 'OnPrompt', 'challenge', expected);
            [challengeAudio, challengeFs, ci] = vsIO('record', ...
                sprintf('Say the %d displayed digits', cfg.ChallengeLength));
            notifyGUI(guiHooks, 'OnAudio', 'challenge', challengeAudio, challengeFs);
            if ~ci.SpeechFound
                pass = false;
                f2report = struct('Reason', 'No challenge speech detected.', ...
                                  'Expected', expected);
            else
                [pass, f2report] = runChallenge(challengeAudio, challengeFs, ...
                                                 db, candidate, expected, cfg);
            end
            notifyGUI(guiHooks, 'OnFactor2', pass, f2report);
            report.Factor2 = f2report;
            report.Stage = 'factor2';
            report.Reason = f2report.Reason;
            if pass
                ok = true;
                id = candidate;
                report.Reason = 'Factor 1 and three-digit Factor 2 passed.';
                fprintf('\nACCESS GRANTED  ->  %s (both factors passed)\n', id);
                return;
            end
            fprintf('[CHALLENGE DENIED] %s\n', f2report.Reason);
            if cAttempt < cfg.MaxChallengeAttempts
                fprintf('[RETRY] A NEW three-digit challenge will be generated.\n');
            end
        end
        % A failed Factor 2 never falls back to allowing more Factor 1
        % attempts inside the current login (prevents bypass by retry).
        fprintf('\nACCESS DENIED: %s\n', report.Reason);
        return;
    end
    if attempt < cfg.MaxAuthAttempts
        fprintf('\n[FACTOR 1 DENIED] %s\n', report.Reason);
    end
end
fprintf('\nACCESS DENIED: %s\n', report.Reason);
end


function [ok, id, report] = verifyFromFiles(audio, fs, expected, enteredID, cfg)
% Files mode is only a diagnostic and must test all three recordings.
[ok1, candidate, rep1, db] = runFactor1(audio(1:2), fs(1:2), cfg);
ok = false;
id = 'REJECTED';
report = struct('Reason', rep1.Reason, 'Stage', 'factor1', ...
                'EnteredID', enteredID, 'Factor1', rep1, 'Factor2', []);
if ~ok1, return; end
if ~isempty(enteredID) && ~strcmp(candidate, enteredID)
    report.Reason = 'Entered ID differs from Factor 1 verified identity.';
    fprintf('OFFLINE TEST DENIED: %s\n', report.Reason);
    return;
end
[ok2, rep2] = runChallenge(audio{3}, fs(3), db, candidate, expected, cfg);
report.Stage = 'factor2';
report.Factor2 = rep2;
report.Reason = rep2.Reason;
if ok2
    ok = true;
    id = candidate;
    report.Reason = 'Both factors passed (offline file diagnostic only).';
    fprintf('\nOFFLINE TEST PASSED  ->  %s (not an independent accuracy test)\n', id);
else
    fprintf('\nOFFLINE TEST DENIED: %s\n', report.Reason);
end
end


function [ok, id, report, db] = runFactor1(audio, fs, cfg)
if ~iscell(audio) || numel(audio) ~= 2 || numel(fs) ~= 2
    error('ParkingSecuritySystem:TwoPhrases', ...
          'Factor 1 requires a roll recording and a full-name recording.');
end
db = loadDatabase(cfg);
model = loadVerifier(cfg);
U = [];
report = struct('Reason', '', 'Stage', 'factor1');
ok = false;
id = 'REJECTED';
for k = 1:2
    fprintf('\n[PREPROCESS] %s: %.2f s, %g Hz\n', cfg.LoginSequence{k}, ...
            size(audio{k}, 1)/fs(k), fs(k));
    u = analyzeUtterance(audio{k}, fs(k), cfg);
    u.UttType = cfg.LoginSequence{k};
    fprintf('[NOISE] %s: %s (one pass)\n', u.UttType, u.NoiseMethod);
    if u.IsSilent || nnz(u.Speech) < 20
        report.Reason = sprintf('No usable speech in %s recording.', u.UttType);
        return;
    end
    if isempty(U), U = u; else, U(end+1) = u; end %#ok<AGROW>
end
% Six-argument mode only changes the PRINTED decision. Four original gates,
% all DTW scores, GMM-UBM LLRs, and thresholds remain exactly the same.
[ok, id, report] = verifySpeaker(U, db, model, cfg, true, true);
report.Stage = 'factor1';
% Avoid a separate focus-stealing MATLAB chart ONLY in GUI mode.
% This does not alter the original verification report or any score/decision.
if ~isfield(cfg, 'DisableVerificationPlot') || ~cfg.DisableVerificationPlot
    vsIO('plotverification', report);
end
% The chart can take focus away from the Command Window on desktop MATLAB.
% Return focus before showing the random digits (no audio recording yet).
if ok && (~isfield(cfg, 'DisableVerificationPlot') || ~cfg.DisableVerificationPlot)
    try
        commandwindow;
    catch
        % Headless or restricted MATLAB sessions may not expose the desktop.
    end
end
end


function [ok, report] = runChallenge(audio, fs, db, verifiedRoll, expected, cfg)
fprintf('\n[PREPROCESS] challenge: %.2f s, %g Hz\n', size(audio,1)/fs, fs);
U = analyzeUtterance(audio, fs, cfg);
U.UttType = 'challenge';
fprintf('[NOISE] challenge: %s (one pass)\n', U.NoiseMethod);
% A/B diagnostic: reprocess the SAME original audio with the original
% quietest-frame noise estimator, never reprocess the denoised waveform.
Uquiet = [];
if cfg.ChallengeNoiseDiagnostic && cfg.SpectralSubtraction && ...
        ~isempty(cfg.AmbientNoiseProfile)
    quietCfg=cfg;
    quietCfg.AmbientNoiseProfile=[];
    Uquiet=analyzeUtterance(audio,fs,quietCfg);
end
[ok, report] = verifyChallenge(U, db, verifiedRoll, expected, cfg, true,Uquiet);
end


function db = loadDatabase(cfg)
if ~isfile(cfg.DatabaseFile)
    error('ParkingSecuritySystem:NoDatabase', ...
          'No enrollment database; run ENROLL_STUDENTS.m first.');
end
db = load(cfg.DatabaseFile);
if ~isfield(db, 'DatabaseVersion') || db.DatabaseVersion < 6 || ...
        ~isfield(db, 'UBM') || ~isfield(db.Students, 'Digits')
    error('ParkingSecuritySystem:OldDatabase', ...
          'Three-digit enrollment format required. Re-run enrollment.');
end
end


function model = loadVerifier(cfg)
if ~isfile(cfg.VerifierModelFile)
    error('ParkingSecuritySystem:NoVerifier', ...
          'No verifier model; run ENROLL_STUDENTS.m first.');
end
m = load(cfg.VerifierModelFile);
model = m.VerifierModel;
end


function validateEnteredID(enteredID, db)
% Only an exact 7-digit enrolled ID may proceed. Never silently infer one.
if isempty(regexp(enteredID, '^\d{7}$', 'once'))
    error('ParkingSecuritySystem:InvalidEnteredID', ...
        'Enter exactly seven digits (example 1234567).');
end
if ~any(strcmp({db.Students.Roll}, enteredID))
    error('ParkingSecuritySystem:UnknownEnteredID', ...
        'Entered ID is not enrolled. Enrollment must be run separately.');
end
end


function notifyGUI(hooks, eventName, varargin)
% Optional, non-authoritative display callbacks. The ORIGINAL scores and
% access decision NEVER depend on the GUI callback return value.
if ~isstruct(hooks) || ~isfield(hooks, eventName), return; end
h = hooks.(eventName);
if ~isa(h, 'function_handle'), return; end
try
    feval(h, varargin{:});
catch ME
    fprintf('[GUI] Could not update %s: %s\n', eventName, ME.message);
end
end
