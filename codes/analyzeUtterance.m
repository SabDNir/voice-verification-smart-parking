function U = analyzeUtterance(audio, fs, cfg)
%ANALYZEUTTERANCE  Preprocess and extract MFCC features for recognition.
%   Recognition: CMVN MFCC + delta for spoken-content DTW.
%   Speaker model: mean-normalized cepstra for GMM-UBM scoring.
%   Does not compute replay/CQCC features or persist microphone audio.
if nargin < 3 || isempty(cfg), cfg = vsConfig(); end
if size(audio, 2) > 1
    audio = mean(double(audio), 2);
end
audio = double(audio(:));
[frames, ~, clean, fs8, p1] = preprocessAudio(audio, fs, cfg);
[fDyn, stat, ~, ~, extra] = extractMFCC_Delta(frames, fs8, cfg);
fDyn = orientFeatures(fDyn, size(fDyn, 2));
logE = extra.LogEnergy(:);
speech = logE > max(logE) - cfg.SpeechFloorDb / 10 * log(10);
if nnz(speech) < 10
    speech = true(size(logE));
end
X = extra.SpeakerCep(speech, :);
U = struct();
U.Dyn        = fDyn;
U.Speech     = speech;
speechFeatures = fDyn(speech, :);
U.Content    = cmvnNormalize(speechFeatures, size(speechFeatures, 2));
% Keep pre-CMVN digit features as well. A three-digit phrase is built from
% consecutive isolated-digit features and normalised AFTER concatenation.
U.DigitSeg   = speechFeatures;
U.VQ         = X - mean(X, 1);
U.Clean      = clean;
U.Fs8        = fs8;
U.StaticMFCC = stat;
U.Duration   = numel(clean) / fs8;
U.IsSilent   = p1.IsSilent;
U.UttType    = 'roll';  % caller sets 'roll', 'name', or 'challenge'
U.NoiseMethod = p1.NoiseMethod;
end
