function CALIBRATE_FACTOR2()
%CALIBRATE_FACTOR2 Optional supervised DIGIT-ONLY speaker-gate experiment.
% Does NOT change Factor 1. Captures no WAVs or biometric model updates.
% Needs 12 genuine + 12 impostor correctly spoken 3-digit challenges, from
% >=3 different real impostors. Holds out four trials per class to evaluate
% the candidate threshold. Only explicitly approved, separated results are
% used; otherwise Factor 2 keeps its original baseline threshold (0.30).
% A small same-session test does NOT prove real-world spoof resistance.
cfg = vsConfig();
checkModelsReady(cfg);
digitModel = checkDigitVoiceReady(cfg);
db = load(cfg.DatabaseFile);
N_GENUINE = 12; N_IMPOSTOR = 12; N_TRAIN = 8;
MARGIN = 0.05;
fprintf('\nDIGIT-ONLY FACTOR 2 VOICE CALIBRATION (no audio saved)\n');
fprintf('Collect %d genuine + %d impostor trials from >=3 distinct impostors.\n', ...
    N_GENUINE,N_IMPOSTOR);
fprintf('Have an operator confirm the ACTUAL speaker at every trial.\n');
roll = strtrim(input('Verified enrolled roll to calibrate: ','s'));
owner = find(strcmp(digitModel.Rolls,roll),1);
if isempty(owner)
    error('ParkingSecuritySystem:NotDigitEnrolled', ...
        '%s lacks a digit-only model. Add all 10 isolated digits and re-enroll.',roll);
end
ready = strtrim(input('Operator and participants ready? Type YES: ','s'));
if ~strcmp(ready,'YES')
    fprintf('Cancelled. No threshold changed.\n');
    return;
end
cfg.AmbientNoiseProfile = [];
if cfg.UseAmbientNoiseReference && cfg.SpectralSubtraction
    [ambient,fs,info] = vsIO('recordnoise');
    if info.Valid
        [profile,reason] = buildAmbientNoiseProfile(ambient,fs,cfg);
        if ~isempty(profile)
            cfg.AmbientNoiseProfile = profile;
            fprintf('[NOISE] Using shared 3-second ambient profile.\n');
        else
            fprintf('[NOISE] Invalid profile (%s); using quiet-frame fallback.\n',reason);
        end
    else
        fprintf('[NOISE] Noise reference unavailable; using quiet-frame fallback.\n');
    end
    clear ambient
end
mode = digitVoiceNoiseMode(cfg);
N = N_GENUINE + N_IMPOSTOR;
scores = nan(N,1); ranks = nan(N,1); quietScores = nan(N,1);
actual = cell(N,1);
labels = [true(N_GENUINE,1); false(N_IMPOSTOR,1)];
rng('shuffle');
for j=1:N
    if labels(j)
        who = roll;
        fprintf('\nGENUINE %d/%d: %s speaks as themselves.\n',j,N_GENUINE,roll);
    else
        who = strtrim(input(sprintf('\nIMPOSTOR %d/%d: actual speaker ID/name: ', ...
            j-N_GENUINE,N_IMPOSTOR),'s'));
        if isempty(who) || strcmp(who,roll)
            fprintf('Actual speaker must be someone OTHER than %s. Try again.\n',roll);
            return;
        end
        fprintf('Impostor %s must speak correct random digits while claiming %s.\n',who,roll);
    end
    actual{j} = who;
    gotValid = false;
    for attempt=1:3
        code = randi([0,9],1,3);
        fprintf('CHALLENGE: %s (pause %.2f-%.2f s between digits)\n', ...
            strtrim(sprintf('%d ',code)),cfg.ChallengePauseLowSec,cfg.ChallengePauseHighSec);
        [raw,rawFs,rec] = vsIO('record','Speak the three displayed digits');
        if ~rec.SpeechFound
            clear raw
            fprintf('No speech detected; new challenge.\n');
            continue;
        end
        U = analyzeUtterance(raw,rawFs,cfg);
        if cfg.ChallengeNoiseDiagnostic && ~isempty(cfg.AmbientNoiseProfile)
            quietCfg = cfg; quietCfg.AmbientNoiseProfile = [];
            Uquiet = analyzeUtterance(raw,rawFs,quietCfg);
        else
            Uquiet = [];
        end
        clear raw
        if U.IsSilent || size(U.VQ,1)<5
            fprintf('Insufficient speech; new challenge.\n');
            continue;
        end
        [pieces,seg,digitFrames] = segmentChallengeDigits(U,cfg);
        if ~seg.Valid || numel(digitFrames)~=3 || ...
                any(cellfun(@isempty,digitFrames))
            fprintf('Digit segmentation failed; new challenge.\n');
            continue;
        end
        content = scoreChallengeDigits(pieces,db,roll,code,cfg);
        if ~content.ContentPass
            fprintf('Digits mismatched or uncertain; VOICE trial discarded. New challenge.\n');
            continue;
        end
        % Same model AND the same per-digit frame processing used live.
        X = vertcat(digitFrames{:});
        ss = voiceModel('llr',X,digitModel.VoiceMeans,digitModel.UBM);
        [~,ordering] = sort(ss,'descend');
        scores(j) = ss(owner);
        ranks(j) = find(ordering==owner,1);
        if ~isempty(Uquiet) && ~Uquiet.IsSilent
            [~,sqSeg,quietFrames] = segmentChallengeDigits(Uquiet,cfg);
            if sqSeg.Valid && all(~cellfun(@isempty,quietFrames))
                qs = voiceModel('llr',vertcat(quietFrames{:}), ...
                    digitModel.VoiceMeans,digitModel.UBM);
                quietScores(j) = qs(owner);
            end
        end
        fprintf('Owner digit-only LLR %+0.3f, rank %d\n',scores(j),ranks(j));
        gotValid = true;
        break;
    end
    if ~gotValid
        fprintf('Trial could not be collected after 3 new challenges.\n');
        fprintf('Cancelled. No threshold or partial calibration will be saved.\n');
        return;
    end
end
impIDs = unique(actual(~labels));
if numel(impIDs)<3
    fprintf('\nOnly %d distinct impostors were tested; need at least 3.\n',numel(impIDs));
    fprintf('No calibration will be applied. Repeat with different impostors.\n');
    return;
end
% Hold-out split: 8 training and 4 validation trials per group. Guarantee
% at least one TRAINING attempt from each of three distinct impostors.
gOrder = randperm(N_GENUINE);
impActual = actual(N_GENUINE+1:end);
impTrain = [];
for t=1:min(3,numel(impIDs))
    positions = find(strcmp(impActual,impIDs{t}));
    impTrain(end+1) = positions(1); %#ok<AGROW>
end
remaining = setdiff(1:N_IMPOSTOR,impTrain);
remaining = remaining(randperm(numel(remaining)));
impTrain = [impTrain,remaining(1:(N_TRAIN-numel(impTrain)))];
impValid = setdiff(1:N_IMPOSTOR,impTrain);
gTrain = scores(gOrder(1:N_TRAIN));
gTrainRank = ranks(gOrder(1:N_TRAIN));
gValid = scores(gOrder(N_TRAIN+1:end));
gValidRank = ranks(gOrder(N_TRAIN+1:end));
iTrain = scores(N_GENUINE+impTrain);
iValid = scores(N_GENUINE+impValid);
iValidRank = ranks(N_GENUINE+impValid);
lowG = vsUtils('prctile',gTrain,10);
highI = max(iTrain);
trainRank1 = mean(gTrainRank==1);
separable = isfinite(lowG) && isfinite(highI) && ...
    (highI + MARGIN < lowG) && trainRank1>=0.875;
candidate = cfg.ChallengeVoiceGate;
if separable
    candidate = (lowG + highI + MARGIN)/2;
end
baselineValidFRR = mean(gValid<cfg.ChallengeVoiceGate | gValidRank~=1);
baselineValidFAR = mean(iValid>=cfg.ChallengeVoiceGate & iValidRank==1);
newValidFRR = mean(gValid<candidate | gValidRank~=1);
newValidFAR = mean(iValid>=candidate & iValidRank==1);
% A separate threshold is authorized ONLY if it remains separated on
% independent held-out trials; never silently relax baseline security.
validated = separable && newValidFAR==0 && ...
    newValidFAR<=baselineValidFAR && newValidFRR<=baselineValidFRR && ...
    newValidFRR<=0.25;
fprintf('\n-------------------------------------------------------\n');
fprintf('DIGIT-ONLY CALIBRATION REPORT for %s (%s noise)\n',roll,mode);
fprintf('Distinct impostors                    : %d\n',numel(impIDs));
fprintf('Training genuine 10th percentile      : %.3f\n',lowG);
fprintf('Training max impostor LLR             : %.3f\n',highI);
fprintf('Training genuine rank-1               : %.0f%%\n',100*trainRank1);
fprintf('Baseline held-out FRR / FAR          : %.0f%% / %.0f%%\n', ...
    100*baselineValidFRR,100*baselineValidFAR);
if separable
    fprintf('Candidate digit-only voice threshold  : %.3f\n',candidate);
    fprintf('Candidate held-out FRR / FAR         : %.0f%% / %.0f%%\n', ...
        100*newValidFRR,100*newValidFAR);
else
    fprintf('No separating threshold in TRAINING data.\n');
end
fprintf('Held-out result                        : %s\n',passstr(validated));
fprintf('Controlled same-session results are NOT guaranteed security estimates.\n');
fprintf('-------------------------------------------------------\n');
if validated
    action = strtrim(input(['Type APPLY to save numeric results and ENABLE this ' ...
        'threshold, SAVE for diagnostics only, anything else to cancel: '],'s'));
else
    action = strtrim(input('Type SAVE for numeric diagnostics only, or anything else to cancel: ','s'));
end
if ~strcmp(action,'APPLY') && ~strcmp(action,'SAVE')
    fprintf('Calibration cancelled; baseline retained.\n');
    return;
end
calibrated = validated && strcmp(action,'APPLY');
e = struct();
e.Roll=roll; e.Calibrated=calibrated;
if calibrated, e.Threshold=candidate;
else, e.Threshold=cfg.ChallengeVoiceGate; end
e.ModelVersion=digitModel.ModelVersion;
e.DigitModelBuildTimestamp=digitModel.BuildTimestamp;
e.PipelineVersion=cfg.PipelineVersion;
e.DatabaseBuildDate=db.BuildDate;
e.NoiseMode=mode;
e.NumStudents=numel(digitModel.Rolls);
e.NumGenuine=N_GENUINE; e.NumImpostor=N_IMPOSTOR;
e.DistinctImpostors=numel(impIDs);
e.GenuineLLR=scores(labels); e.ImpostorLLR=scores(~labels);
e.GenuineRank=ranks(labels); e.ImpostorRank=ranks(~labels);
e.QuietLLR=quietScores; e.Candidate=candidate;
e.TrainingSeparable=separable; e.HeldOutValidated=validated;
e.BaselineHeldOutFRR=baselineValidFRR;
e.BaselineHeldOutFAR=baselineValidFAR;
e.CandidateHeldOutFRR=newValidFRR;
e.CandidateHeldOutFAR=newValidFAR;
e.CollectedAt=datestr(now);
Entries=e; %#ok<NASGU>
if isfile(cfg.Factor2CalibrationFile)
    prev=load(cfg.Factor2CalibrationFile,'Entries');
    if isfield(prev,'Entries') && isstruct(prev.Entries) && ~isempty(prev.Entries)
        try
            prior=prev.Entries;
            ix=find(strcmp({prior.Roll},roll),1);
            if isempty(ix), prior(end+1)=e;
            else, prior(ix)=e; end
            Entries=prior;
        catch
            fprintf('[NOTE] Old calibration format ignored; replacing it.\n');
        end
    end
end
save(cfg.Factor2CalibrationFile,'Entries');
if calibrated
    fprintf('APPLIED %.3f to %s (digit-only Factor 2 only).\n',candidate,roll);
else
    fprintf('Saved numeric diagnostics ONLY. Baseline %.2f is still active.\n', ...
        cfg.ChallengeVoiceGate);
end
end

function s=passstr(v)
if v,s='PASS';else,s='FAIL';end
end
