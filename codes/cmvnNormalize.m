function [Xn, mu, sigma] = cmvnNormalize(X, expectedDim)
%% ====================================================================
%  FROZEN - DO NOT EDIT WITHOUT GROUP AGREEMENT
%  ====================================================================
%  This file carries the fix for defect D2.
%
%  D2: normalisation ran along the coefficient axis instead of the time
%  axis. (X - mean(X,2))./std(X,0,2) on a [T x 20] matrix forces every
%  frame to zero mean and unit variance across its own 20 heterogeneous
%  coefficients, pooling static MFCCs of magnitude ~10 with Deltas of
%  magnitude ~0.1. The fix is one character of index - dim 1 instead of
%  dim 2 - and it changes every DTW distance in the system.
%
%  EnrolledDatabase.mat files in v1 format have the wrong-axis version
%  baked into their stored features, which is why verifySpeaker rejects
%  them outright rather than trying to interpret them.
%
%  Do not "optimise" or reorder this function. If you think it is wrong,
%  raise it with the group before touching it.
%% ====================================================================
%
% Cepstral mean and variance normalisation along the TIME axis.
%
% Replaces (X - mean(X,2))./std(X,0,2), which on a [T x 20] matrix forced
% every frame to zero mean and unit variance across its own 20 heterogeneous
% coefficients - pooling static MFCCs of magnitude ~10 with Deltas of
% magnitude ~0.1, and discarding the absolute cepstral level frame by frame.
%
% Note that CMVN deliberately REMOVES the long-term average spectrum, which
% carries both channel colouration and much of speaker identity. That is
% correct for CONTENT matching, and it is exactly why the CMVN'd features
% must not be the only evidence used for speaker verification. The discarded
% mean is recovered as a speaker cue in speakerFeatures.

% v3: callers that already hold [frames x coeffs] pass expectedDim. Without
% it, a segment with fewer frames than coefficients (a short digit) would be
% mistaken for a transposed matrix by the frames-outnumber-coeffs rule.
if nargin >= 2 && ~isempty(expectedDim)
    X = orientFeatures(X, expectedDim);
else
    X = orientFeatures(X);
end
mu    = mean(X, 1);
sigma = std(X, 0, 1);
sigma(sigma < 1e-8) = 1e-8;
Xn    = (X - mu) ./ sigma;
end
