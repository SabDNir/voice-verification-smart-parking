function saveVerificationLog(granted, verifiedID, report, claimedID, mode, cfg)
%SAVEVERIFICATIONLOG  Append local verification metadata (no audio saved).
% Logging is deliberately non-authoritative: any disk/logging failure is
% reported as a warning and cannot change the authentication decision.
% Files live beside codes/, so replacing codes/ preserves existing history.

try
    if nargin < 6 || isempty(cfg), cfg = vsConfig(); end
    if nargin < 5 || isempty(mode), mode = 'GUI'; end
    if nargin < 4, claimedID = ''; end
    if nargin < 3 || ~isstruct(report), report = struct(); end
    if nargin < 2 || isempty(verifiedID), verifiedID = 'REJECTED'; end

    logDir = fullfile(cfg.ProjectDir, 'verification_logs');
    if ~exist(logDir, 'dir')
        [made, msg] = mkdir(logDir);
        if ~made, error('Log directory cannot be created: %s', msg); end
    end
    csvPath = fullfile(logDir, 'verification_history.csv');

    when = datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF');
    % No calls to rng/randi here: logging must not influence challenges.
    sessionID = datestr(now, 'yyyymmdd_HHMMSSFFF');
    claim = char(string(claimedID));
    if isempty(claim), claim = char(string(getField(report, 'EnteredID', ''))); end
    reason = char(string(getField(report, 'Reason', '')));
    stage = char(string(getField(report, 'Stage', 'unknown')));
    f1 = getField(report, 'Factor1', []);
    f2 = getField(report, 'Factor2', []);
    if ~isstruct(f1), f1 = struct(); end
    if ~isstruct(f2), f2 = struct(); end
    best = char(string(getField(f1, 'BestRoll', '')));

    gates = getField(f1, 'Gates', struct());
    if ~isstruct(gates), gates = struct(); end
    gatePass = hasAllGates(gates);
    claimPass = gatePass && strcmp(best, claim);
    if strcmpi(stage, 'error')
        f1State = 'ERROR';
    elseif ~isempty(fieldnames(f1)) || strcmpi(stage, 'factor1')
        f1State = 'FAILED';
        if claimPass, f1State = 'PASSED'; end
    else
        f1State = 'NOT_RUN';
    end
    if strcmpi(stage, 'claim'), f1State = 'NOT_RUN'; end

    f2State = 'NOT_RUN';
    if ~isempty(fieldnames(f2))
        f2State = 'FAILED';
        if granted, f2State = 'PASSED'; end
    end
    decision = 'DENIED';
    if granted, decision = 'GRANTED'; end
    if strcmpi(stage, 'error'), decision = 'ERROR'; end
    authenticatedID = '';
    if claimPass, authenticatedID = best; end

    ix = [];
    rolls = getField(f1, 'Rolls', {});
    if iscell(rolls), ix = find(strcmp(rolls, best), 1); end
    phrase = []; voice = [];
    sd = getField(f1, 'Sd', []);
    llr = getField(f1, 'Voice', []);
    if ~isempty(ix)
        if isnumeric(sd) && numel(sd) >= ix, phrase = sd(ix); end
        if isnumeric(llr) && numel(llr) >= ix, voice = llr(ix); end
    end
    margins = getField(f2, 'DigitMargins', []);
    if ~isnumeric(margins), margins = []; end
    margins(end+1:3) = NaN;

    headers = {'Timestamp','SessionID','Mode','ClaimedID','BestSpeakerMatch', ...
        'VerifiedID','Factor1Status','F1PhraseScore','F1PhraseThreshold', ...
        'F1VoiceLLR','F1VoiceGate','F1VoiceRank','G1Phrase', ...
        'G2Consistent','G3VoiceRank','G4VoiceLevel','Factor2Status', ...
        'ExpectedDigits','RecognizedDigits','Digit1Margin','Digit2Margin', ...
        'Digit3Margin','F2SpeakerRank','F2LLR','F2VoiceGate', ...
        'F2ContentPass','F2VoicePass','Decision','Stage','Reason'};
    values = {when, sessionID, mode, claim, best, authenticatedID, ...
        f1State, numberText(phrase), numberText(getField(f1,'ThetaPhrase',[])), ...
        numberText(voice), numberText(getField(f1,'VoiceGate',[])), ...
        numberText(getField(f1,'VoiceRank',[])), ...
        boolText(getField(gates,'G1_Phrase',[])), ...
        boolText(getField(gates,'G2_Consistent',[])), ...
        boolText(getField(gates,'G3_VoiceRank',[])), ...
        boolText(getField(gates,'G4_VoiceLevel',[])), f2State, ...
        digitText(getField(f2,'Expected',[])), ...
        digitText(getField(f2,'Recognized',[])), ...
        numberText(margins(1)), numberText(margins(2)), ...
        numberText(margins(3)), ...
        numberText(getField(f2,'VoiceRank',[])), ...
        numberText(getField(f2,'VoiceLLR',[])), ...
        numberText(getField(f2,'VoiceGate',[])), ...
        boolText(getField(f2,'ContentPass',[])), ...
        boolText(getField(f2,'VoicePass',[])), ...
        decision, stage, reason};

    newCSV = ~isfile(csvPath);
    if ~newCSV
        info = dir(csvPath);
        newCSV = isempty(info) || info.bytes == 0;
    end
    fid = fopen(csvPath, 'a');
    if fid == -1, error('Cannot open CSV log: %s', csvPath); end
    csvCleanup = onCleanup(@() fclose(fid));
    if newCSV, fprintf(fid, '%s\n', strjoin(headers, ',')); end
    fprintf(fid, '%s\n', strjoin(cellfun(@quoteCSV, values, ...
        'UniformOutput', false), ','));
    clear csvCleanup  % flush and close the CSV file
    fprintf('[LOG] Saved verification CSV to %s\n', csvPath);
catch ME
    % Never make logging an additional authentication gate.
    warning('VerificationLog:WriteFailure', ...
        'Verification result unchanged; could not save log: %s', ME.message);
end
end

function value = getField(s, name, fallback)
if isstruct(s) && isscalar(s) && isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end

function passed = hasAllGates(g)
names = {'G1_Phrase','G2_Consistent','G3_VoiceRank','G4_VoiceLevel'};
passed = all(cellfun(@(k) isfield(g,k) && isequal(g.(k),true), names));
end

function s = numberText(v)
s = '';
if isnumeric(v) && isscalar(v)
    if isnan(v), s = 'NaN';
    elseif isinf(v), s = 'Inf'; if v < 0, s = '-Inf'; end
    else, s = sprintf('%.6g', v);
    end
end
end

function s = boolText(v)
s = '';
if islogical(v) && isscalar(v)
    if v, s = 'PASS'; else, s = 'FAIL'; end
end
end

function s = digitText(v)
s = '';
if isnumeric(v) && ~isempty(v)
    pieces = cell(1, numel(v));
    for i = 1:numel(v)
        if isnan(v(i)), pieces{i} = '?';
        elseif isfinite(v(i)), pieces{i} = sprintf('%d',v(i));
        else, pieces{i} = '?';
        end
    end
    s = strjoin(pieces, ' ');
end
end

function out = quoteCSV(value)
if isempty(value), out = '""'; return; end
value = char(string(value));
value = regexprep(value, '[\r\n\t]', ' ');
% Avoid accidental spreadsheet formula execution for free-text fields.
if ~isempty(value) && (any(value(1) == ['=' '@']) || ...
        (any(value(1) == ['+' '-']) && ...
         isempty(regexp(value, '^[+-](?:[0-9]|Inf)', 'once'))))
    value = ['''' value];
end
out = ['"' strrep(value, '"', '""') '"'];
end
