function [passed,report]=verifyChallenge(U,db,verifiedRoll,expected,cfg,verbose,Uquiet,digitModel)
%VERIFYCHALLENGE Factor 2: THREE independent digit checks and same speaker.
% Reuses original MFCC + normalized DTW and UNMODIFIED GMM-UBM algorithm.
% Factor 2 uses an INDEPENDENT digit-only GMM-UBM, not the Factor 1 model.
% Roll/name authentication is performed separately and left unchanged.
% The expected code NEVER guides segmentation or selects a score winner.
% Optional Uquiet is separately preprocessed from the SAME raw challenge
% audio for diagnostics ONLY. It cannot turn a failing trial into a pass.
if nargin<5 || isempty(cfg),cfg=vsConfig();end
if nargin<6,verbose=true;end
if nargin<7,Uquiet=[];end
% digitModel argument is for synthetic regression tests. The LIVE path loads
% the separately enrolled persistent model and checks its compatibility.
if nargin<8 || isempty(digitModel)
    digitModel=checkDigitVoiceReady(cfg,db);
end
expected=double(expected(:).');
if numel(expected)~=3 || any(expected<0 | expected>9 | expected~=floor(expected))
    error('ParkingSecuritySystem:BadChallenge','Challenge must have three digits 0..9.');
end
owner=find(strcmp({db.Students.Roll},char(verifiedRoll)),1);
if isempty(owner)
    error('ParkingSecuritySystem:MissingOwner','Claimed Factor 1 identity is not enrolled.');
end
[gate,gateSource]=factor2VoiceGate(verifiedRoll,db,cfg,digitModel);
digitOwner=find(strcmp(digitModel.Rolls,char(verifiedRoll)),1);
report=struct('Expected',expected,'Recognized',nan(1,3), ...
    'RunnerUp',nan(1,3),'DigitMargins',nan(1,3), ...
    'DigitDistances',inf(3,10),'TemplateSpeakers',0,'OwnerDigitTemplates',false, ...
    'SegmentTimes',[],'SegmentationPass',false,'ContentPass',false, ...
    'VoiceRank',inf,'VoiceLLR',-inf,'VoicePass',false, ...
    'VoiceRankPass',false,'VoiceLevelPass',false,'VoiceGate',gate, ...
    'VoiceGateSource',gateSource,'TopSpeakerRolls',{{}},'TopSpeakerLLRs',[], ...
    'DigitOwnerModelAvailable',~isempty(digitOwner), ...
    'LegacyLLR',nan,'LegacyRank',nan,'QuietLLR',nan,'QuietRank',nan, ...
    'QuietDigits',nan(1,3),'QuietMargins',nan(1,3), ...
    'NoiseMethod',U.NoiseMethod,'Reason','');
passed=false;
voicePieces={};
if ~U.IsSilent && size(U.Content,1)>=cfg.ChallengeMinFrames && ...
        size(U.VQ,1)>=5 && all(isfinite(U.Content(:)))
    if isfield(U,'ChallengeSegments') && ~isempty(U.ChallengeSegments)
        pieces=U.ChallengeSegments; % synthetic TEST_CHALLENGE only
        seg=struct('Valid',numel(pieces)==3, 'Reason','', ...
                   'IntervalsSec',[],'GapSec',[]);
    else
        [pieces,seg,voicePieces]=segmentChallengeDigits(U,cfg);
    end
    report.SegmentationPass=seg.Valid;
    if seg.Valid
        report.SegmentTimes=seg.IntervalsSec;
        d=scoreChallengeDigits(pieces,db,verifiedRoll,expected,cfg);
        report.Recognized=d.Recognized;
        report.RunnerUp=d.RunnerUp;
        report.DigitMargins=d.Margins;
        report.DigitDistances=d.Distances;
        report.TemplateSpeakers=d.TemplateSpeakers;
        report.OwnerDigitTemplates=d.OwnerTemplate;
        report.ContentPass=d.ContentPass;
        contentReason=d.Reason;
    else
        contentReason=seg.Reason;
    end
    % CRITICAL: only DIGIT-TRAINED models decide the challenge speaker.
    % The unchanged original mixed-speech speaker model is used for Factor 1.
    if seg.Valid && numel(voicePieces)==3 && ...
            all(~cellfun(@isempty,voicePieces))
        % Per-digit mean centering mirrors enrollment of isolated digits.
        fv=vertcat(voicePieces{:});
    else
        % Diagnostic only when segmentation fails; content gate prevents access.
        % Synthetic regression tests supply only U.VQ here.
        fv=voiceModel('features',U.VQ);
    end
    s=voiceModel('llr',fv,digitModel.VoiceMeans,digitModel.UBM);
    [sorted,order]=sort(s,'descend');
    top=order(1:min(3,numel(order)));
    report.TopSpeakerRolls=digitModel.Rolls(top);
    report.TopSpeakerLLRs=sorted(1:numel(top));
    if ~isempty(digitOwner)
        report.VoiceRank=find(order==digitOwner,1);
        report.VoiceLLR=s(digitOwner);
        report.VoiceRankPass=report.VoiceRank==1;
        report.VoiceLevelPass=isfinite(report.VoiceLLR) && report.VoiceLLR>=gate;
        report.VoicePass=report.VoiceRankPass && report.VoiceLevelPass;
    end
    % Optional A/B comparison only; cannot change the Factor 2 decision.
    if cfg.ChallengeLegacyVoiceDiagnostic
        oldScores=voiceModel('llr',fv,db.VoiceMeans,db.UBM);
        [~,oldOrder]=sort(oldScores,'descend');
        report.LegacyRank=find(oldOrder==owner,1);
        report.LegacyLLR=oldScores(owner);
    end
else
    contentReason='No usable three-digit speech was detected.';
end
% Noise-processing A/B diagnostic. Both paths process the ORIGINAL raw
% audio independently; neither denoises the other one's output. The main
% path above alone determines access. Nothing is saved to disk.
if ~isempty(Uquiet) && ~Uquiet.IsSilent && size(Uquiet.VQ,1)>=5
    fv=voiceModel('features',Uquiet.VQ);
    [altPieces,altVoiceSeg,quietVoiceFrames]=segmentChallengeDigits(Uquiet,cfg);
    if altVoiceSeg.Valid && all(~cellfun(@isempty,quietVoiceFrames))
        fv=vertcat(quietVoiceFrames{:});
    end
    sq=voiceModel('llr',fv,digitModel.VoiceMeans,digitModel.UBM);
    [~,ordq]=sort(sq,'descend');
    if ~isempty(digitOwner)
        report.QuietLLR=sq(digitOwner);
        report.QuietRank=find(ordq==digitOwner,1);
    end
    if cfg.ChallengeNoiseDigitDiagnostic
        if altVoiceSeg.Valid
            alt=scoreChallengeDigits(altPieces,db,verifiedRoll,expected,cfg);
            report.QuietDigits=alt.Recognized;
            report.QuietMargins=alt.Margins;
        end
    end
end
passed=report.ContentPass && report.VoicePass;
reasons={};
if ~report.ContentPass
    reasons{end+1}=contentReason; %#ok<AGROW>
end
if isempty(digitOwner)
    reasons{end+1}='No dedicated digit-voice model for the verified student (need all ten isolated digits).'; %#ok<AGROW>
elseif ~report.VoiceRankPass
    reasons{end+1}=sprintf('challenge voice ranked %s (must be 1)', ...
        num2str(report.VoiceRank)); %#ok<AGROW>
end
if ~isempty(digitOwner) && ~report.VoiceLevelPass
    reasons{end+1}=sprintf('challenge LLR %.2f below %.2f', ...
        report.VoiceLLR,gate); %#ok<AGROW>
end
if passed
    report.Reason='All three digits and the verified speaker matched in the digit-only GMM-UBM.';
else
    report.Reason=strjoin(reasons,'; ');
end
if verbose,printChallenge(report,verifiedRoll,cfg);end
end

function printChallenge(r,roll,cfg)
line=repmat('-',1,72);
fprintf('\n%s\n          FACTOR 2 - THREE INDEPENDENT DIGITS\n%s\n',line,line);
fprintf('Factor 1 verified ID : %s\n',char(roll));
fprintf('Expected             : %s\n',strtrim(sprintf('%d ',r.Expected)));
fprintf('Noise preprocessing  : %s\n',r.NoiseMethod);
if r.SegmentationPass
    fprintf('Segments (seconds)   : %s\n',sprintf('[%.2f-%.2f] ',r.SegmentTimes.'));
    fprintf('Template speakers    : %d (owner templates: %s)\n', ...
        r.TemplateSpeakers,passstr(r.OwnerDigitTemplates));
    fprintf('Recognized           : %s\n',strtrim(sprintf('%d ',r.Recognized)));
    fprintf('Runner-up digits     : %s\n',strtrim(sprintf('%d ',r.RunnerUp)));
    fprintf('Digit margins        : %s (minimum %.3f)\n', ...
        sprintf('%.3f ',r.DigitMargins),cfg.ChallengeDigitMinMargin);
    for k=1:3
        [ordered,ix]=sort(r.DigitDistances(k,:));
        fprintf('  digit %d: first %d (%.3f), second %d (%.3f), expected %d (%.3f)\n', ...
            k,ix(1)-1,ordered(1),ix(2)-1,ordered(2), ...
            r.Expected(k),r.DigitDistances(k,r.Expected(k)+1));
    end
else
    fprintf('Segmentation         : FAILED (clear pauses required)\n');
end
fprintf('Content gate         : %s\n',passstr(r.ContentPass));
fprintf('Digit-only GMM-UBM top speakers (LLR):\n');
for t=1:numel(r.TopSpeakerLLRs)
    fprintf('  #%d  %s  %+.3f\n',t,r.TopSpeakerRolls{t},r.TopSpeakerLLRs(t));
end
if ~r.DigitOwnerModelAvailable
    fprintf('Verified speaker has NO digit-only model (all 10 digits required).\n');
end
fprintf('Same speaker rank    : %s (required 1) %s\n', ...
    num2str(r.VoiceRank),passstr(r.VoiceRankPass));
fprintf('Same speaker LLR     : %.3f (required %.3f) %s\n', ...
    r.VoiceLLR,r.VoiceGate,passstr(r.VoiceLevelPass));
fprintf('Voice threshold      : %s\n',r.VoiceGateSource);
if isfinite(r.LegacyLLR)
    fprintf('Mixed-speech model (DIAGNOSTIC): LLR %.3f, rank %d\n', ...
        r.LegacyLLR,r.LegacyRank);
end
if isfinite(r.QuietLLR)
    fprintf('Noise A/B, same audio: main %s LLR %.3f rank %d | quiet-frame LLR %.3f rank %d\n', ...
        r.NoiseMethod,r.VoiceLLR,r.VoiceRank,r.QuietLLR,r.QuietRank);
    if all(isfinite(r.QuietDigits))
        fprintf('Quiet-frame digits   : %s (diagnostic ONLY)\n', ...
            strtrim(sprintf('%d ',r.QuietDigits)));
        fprintf('Quiet-frame margins  : %s\n',sprintf('%.3f ',r.QuietMargins));
    end
end
if r.ContentPass && r.VoicePass
    fprintf('FACTOR 2 PASSED\n');
else
    fprintf('FACTOR 2 FAILED: %s\n',r.Reason);
end
fprintf('%s\n',line);
end

function s=passstr(tf)
if tf,s='PASS';else,s='FAIL';end
end
