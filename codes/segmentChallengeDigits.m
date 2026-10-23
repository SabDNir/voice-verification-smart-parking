function [segments, info, digitVoiceFrames] = segmentChallengeDigits(U, cfg)
%SEGMENTCHALLENGEDIGITS Energy-only, identity-independent 3-digit segmentation.
% Segments the already-denoised U.Clean ONCE. It NEVER uses the expected
% digits when locating boundaries and NEVER applies spectral subtraction to
% already cleaned speech. The existing MFCC extractor is used per segment.
% If clear pauses are absent, reject and ask for a new challenge rather than
% invent three equal-duration intervals that might confirm a wrong code.
if nargin < 2 || isempty(cfg), cfg = vsConfig(); end
segments = cell(1, cfg.ChallengeLength);
% Optional third output: GMM feature frames, normalized separately for each
% digit. This matches how the independent digit-only models are enrolled.
% Uses the SAME already-denoised segment; no second noise subtraction.
digitVoiceFrames = cell(1, cfg.ChallengeLength);
info = struct('Valid', false, 'Reason', '', 'IntervalsSec', [], ...
              'GapSec', [], 'IslandsFound', 0);
if ~isstruct(U) || ~isfield(U, 'Clean') || ~isfield(U, 'Fs8') || ...
        isempty(U.Clean) || ~isfinite(U.Fs8) || U.Fs8 <= 0
    info.Reason = 'Preprocessed challenge waveform is unavailable.';
    return;
end
x = double(U.Clean(:)); fs = U.Fs8;
if any(~isfinite(x)) || numel(x) < round(0.45*fs)
    info.Reason = 'The challenge recording is too short or invalid.';
    return;
end
win = max(1, round(0.020*fs));
hop = max(1, round(0.010*fs));
n = floor((numel(x)-win)/hop)+1;
e = zeros(n,1);
for k=1:n
    v = x((k-1)*hop+(1:win));
    e(k) = sqrt(mean(v.^2));
end
e = conv(e, ones(3,1)/3, 'same');
lo = vsUtils('prctile',e,15);
hi = vsUtils('prctile',e,95);
if ~isfinite(hi) || hi <= 1e-4 || hi <= 1.7*max(lo,1e-5)
    info.Reason = 'No clear speech/noise energy contrast for three-digit segmentation.';
    return;
end
thr = max(lo+0.16*(hi-lo), 0.085*hi);
active = e > thr;
% Brief energy dips inside a spoken digit should not split one syllable.
active = fillGaps(active, ceil(cfg.ChallengeBridgeSec*fs/hop));
[starts, ends_] = islands(active);
if isempty(starts)
    info.Reason = 'No reliable individual digit speech intervals detected.';
    return;
end
% Remove short isolated clicks. A genuine digit must have a speech core.
valid = (ends_-starts+1)*hop/fs >= cfg.ChallengeMinCoreSec;
starts = starts(valid); ends_ = ends_(valid);
% If more than three islands remain, only merge short intra-word gaps.
while numel(starts) > cfg.ChallengeLength
    gaps = (starts(2:end)-ends_(1:end-1)-1)*hop/fs;
    [smallest, ix] = min(gaps);
    if smallest > cfg.ChallengeMergeMaxSec, break; end
    ends_(ix) = ends_(ix+1);
    starts(ix+1) = []; ends_(ix+1) = [];
end
info.IslandsFound = numel(starts);
if numel(starts) ~= cfg.ChallengeLength
    info.Reason = sprintf(['Found %d separate speech intervals, expected %d. ' ...
        'Speak each digit separately with about %.1f-%.1f s of silence.'], ...
        numel(starts), cfg.ChallengeLength, ...
        cfg.ChallengePauseLowSec, cfg.ChallengePauseHighSec);
    return;
end
margin = round(cfg.ChallengeEdgePadSec*fs);
intervals = zeros(cfg.ChallengeLength,2);
for j=1:cfg.ChallengeLength
    a = max(1,(starts(j)-1)*hop+1-margin);
    b = min(numel(x),(ends_(j)-1)*hop+win+margin);
    % Intervals in the report are stored in SECONDS (convert below).
    intervals(j,:) = [a/fs,b/fs];
end
% Split the guard bands at the midpoint between adjacent speech cores.
for j=1:(cfg.ChallengeLength-1)
    border = round(((ends_(j)-1)*hop+win + (starts(j+1)-1)*hop+1)/2);
    intervals(j,2) = min(intervals(j,2),border/fs);
    intervals(j+1,1) = max(intervals(j+1,1),(border+1)/fs);
end
for j=1:cfg.ChallengeLength
    a = max(1,floor(intervals(j,1)*fs));
    b = min(numel(x),ceil(intervals(j,2)*fs));
    if b-a+1 < round(cfg.ChallengeMinCoreSec*fs)
        info.Reason = sprintf('Digit position %d was too short to recognize.',j);
        return;
    end
    % Input is ALREADY noise-reduced and at 8 kHz. Disable SS for features.
    noSS = cfg;
    noSS.SpectralSubtraction = false;
    noSS.AmbientNoiseProfile = [];
    one = analyzeUtterance(x(a:b),fs,noSS);
    if one.IsSilent || size(one.Content,1)<cfg.ChallengeMinDigitFrames || ...
            any(~isfinite(one.Content(:)))
        info.Reason = sprintf('Insufficient clean speech for digit %d.',j);
        return;
    end
    segments{j} = one.Content;
    digitVoiceFrames{j} = voiceModel('features',one.VQ);
end
info.Valid = true;
info.IntervalsSec = intervals;
info.GapSec = (starts(2:end)-ends_(1:end-1)-1)*hop/fs;
end

function x = fillGaps(x, maxGap)
[s,e] = islands(x);
for k=1:(numel(s)-1)
    if s(k+1)-e(k)-1 <= maxGap
        x(e(k)+1:s(k+1)-1)=true;
    end
end
end

function [s,e] = islands(x)
x = logical(x(:));
d = diff([false;x;false]);
s = find(d==1);
e = find(d==-1)-1;
end
