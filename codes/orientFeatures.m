function X = orientFeatures(X, expectedDim)
%% ====================================================================
%  FROZEN - DO NOT EDIT WITHOUT GROUP AGREEMENT
%  ====================================================================
%  This file carries the fix for defect D1.
%
%  D1: dtwMatch divided the DTW cost by size(X,2)+size(Y,2). With features
%  stored as [frames x 20] both terms equal 20, so the divisor was the
%  constant 40 for every comparison and the reported "average distance"
%  grew with utterance length. The root cause was an orientation ambiguity:
%  enrolment produced [T x D] while the matcher indexed its input as
%  [D x T]. This function removes that ambiguity for the whole codebase.
%
%  Every feature matrix in Group2_Working/ is [NumFrames x NumCoeffs] and
%  every module funnels through here rather than assuming an orientation.
%  Changing this function silently changes the meaning of every distance,
%  threshold and normalisation downstream. If you think it is wrong, raise
%  it with the group before touching it.
%% ====================================================================
%
% Force [NumFrames x NumCoeffs].
%
% The original code base mixed two conventions: enrolment produced [T x D]
% while the matcher documented and indexed its input as [D x T]. Every
% size(...,2) call therefore returned the coefficient count instead of the
% frame count, which is what caused both the constant-divisor bug and the
% wrong-axis normalisation. This helper removes the ambiguity.

if isempty(X), return; end

if nargin >= 2 && ~isempty(expectedDim)
    if size(X,2) == expectedDim
        return;
    elseif size(X,1) == expectedDim
        X = X.'; return;
    else
        error('ParkingSecuritySystem:DimMismatch', ...
              'Matrix is %dx%d; neither side matches expected dimension %d.', ...
              size(X,1), size(X,2), expectedDim);
    end
end

% A speech utterance always has many more frames than cepstral coefficients.
if size(X,1) < size(X,2)
    X = X.';
end
end
