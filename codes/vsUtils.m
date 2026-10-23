function varargout = vsUtils(op, varargin)
%VSUTILS  Dispatcher for the toolbox-free numerical helpers.
%
%   MATLAB will not let one file call another file's local functions, so the
%   shared helpers live here behind a string switch. Call them as
%
%       w      = vsUtils('hamming', N, periodic)
%       D      = vsUtils('dctmtx', n)
%       y      = vsUtils('prctile', x, p)
%       r      = vsUtils('autocorr', x, maxLag)
%       y      = vsUtils('movmean', x, span)
%       y      = vsUtils('resample', x, p, q)
%       [d,ix,iy] = vsUtils('dtw', X, Y)      X,Y are [D x T]; ix,iy = warping path
%       delta  = vsUtils('firdelta', cepstra, N)
%       d      = vsUtils('dtwnorm', A, B)       A,B are [T x D]; cost per path step
%       C      = vsUtils('lbg', X, K, iters)    VQ codebook, X is [N x D]
%       d      = vsUtils('vqdist', X, C)        mean distance to nearest codeword
%       m      = vsUtils('lowmean', v, k)       mean of the k smallest finite values
%
%   hamming, dctmtx, prctile and xcorr are reimplemented here so that the
%   Image Processing and Statistics toolboxes are NOT required. resample and
%   dtw use the Signal Processing Toolbox when it is present and fall back to
%   local implementations with identical semantics when it is not.
%
%   Shared FIR delta calculation used by extractMFCC_Delta.m.

switch lower(char(op))
    case 'hamming'
        varargout = {hammingLocal(varargin{:})};
    case 'dctmtx'
        varargout = {dctmtxLocal(varargin{:})};
    case 'prctile'
        varargout = {prctileLocal(varargin{:})};
    case 'autocorr'
        varargout = {autocorrLocal(varargin{:})};
    case 'movmean'
        varargout = {movmeanLocal(varargin{:})};
    case 'resample'
        varargout = {resampleSafe(varargin{:})};
    case 'dtw'
        [d, ix, iy] = dtwSafe(varargin{:});
        varargout   = {d, ix, iy};
    case 'firdelta'
        varargout = {firDelta(varargin{:})};
    case 'dtwnorm'
        varargout = {dtwNorm(varargin{:})};
    case 'lbg'
        varargout = {lbgCodebook(varargin{:})};
    case 'vqdist'
        varargout = {vqDistortion(varargin{:})};
    case 'lowmean'
        varargout = {lowMean(varargin{:})};
    otherwise
        error('ParkingSecuritySystem:BadUtil', 'Unknown vsUtils operation "%s".', char(op));
end
end


function w = hammingLocal(N, periodic)
% w[n] = 0.54 - 0.46*cos(2*pi*n/D),  D = N (periodic) or N-1 (symmetric).
if nargin < 2, periodic = false; end
N = round(N);
if N <= 1, w = ones(max(N,1), 1); return; end
n = (0:N-1).';
if periodic
    w = 0.54 - 0.46*cos(2*pi*n / N);
else
    w = 0.54 - 0.46*cos(2*pi*n / (N-1));
end
end


function D = dctmtxLocal(n)
% Orthonormal DCT-II matrix. Local so the Image Processing Toolbox is not
% required (dctmtx lives there).
[cc, rr] = meshgrid(0:n-1);
D = sqrt(2/n) * cos(pi * (2*cc + 1) .* rr / (2*n));
D(1, :) = D(1, :) / sqrt(2);
end


function y = prctileLocal(x, p)
% Linear-interpolation percentile matching MATLAB's prctile. Local so the
% Statistics Toolbox is not required.
x = sort(x(:));
n = numel(x);
if n == 0, y = nan(size(p)); return; end
if n == 1, y = repmat(x, size(p)); return; end
q = 100 * ((1:n) - 0.5) / n;
y = interp1(q, x, p, 'linear', 'extrap');
end


function r = autocorrLocal(x, maxLag)
% One-sided autocorrelation via FFT, r(1) = lag 0. Local so the Signal
% Processing Toolbox xcorr is not required.
x = x(:);
n = numel(x);
m = 2^nextpow2(2*n - 1);
X = fft(x, m);
r = real(ifft(X .* conj(X)));
r = r(1 : min(maxLag + 1, numel(r)));
end


function y = movmeanLocal(x, span)
% Centred moving average with shrinking windows at the edges.
x = x(:);
n = numel(x);
h = floor(span/2);
y = zeros(n, 1);
c = [0; cumsum(x)];
for i = 1:n
    a = max(1, i-h);
    b = min(n, i+h);
    y(i) = (c(b+1) - c(a)) / (b - a + 1);
end
end


function y = resampleSafe(x, p, q)
% Anti-aliased resampling. Uses resample() when the Signal Processing
% Toolbox is present, otherwise an FFT-domain fallback.
if exist('resample', 'file') == 2 || exist('resample', 'builtin') == 5
    try
        g = gcd(round(p), round(q));
        y = resample(x, round(p)/g, round(q)/g);
        return;
    catch
        % fall through
    end
end

n  = numel(x);
nOut = round(n * p / q);
X  = fft(x);
if nOut < n
    keep = floor(nOut/2);
    Y = [X(1:keep+1); conj(flipud(X(2:keep+1)))];
else
    keep = floor(n/2);
    Y = [X(1:keep+1); zeros(nOut - n, 1); X(keep+2:end)];
end
y = real(ifft(Y, nOut)) * (nOut / n);
y = y(:);
end


function [d, ix, iy] = dtwSafe(X, Y)
% DTW between two [D x T] matrices with Euclidean local cost. Uses the
% built-in dtw() when available, otherwise a local dynamic-programming
% implementation with identical semantics.
if exist('dtw', 'file') == 2 || exist('dtw', 'builtin') == 5
    try
        [d, ix, iy] = dtw(X, Y);
        return;
    catch
        % fall through
    end
end

T1 = size(X, 2);
T2 = size(Y, 2);

C = zeros(T1, T2);
for i = 1:T1
    diffs  = Y - X(:, i);
    C(i,:) = sqrt(sum(diffs.^2, 1));
end

D = inf(T1+1, T2+1);
D(1,1) = 0;
for i = 1:T1
    for j = 1:T2
        D(i+1,j+1) = C(i,j) + min([D(i,j+1), D(i+1,j), D(i,j)]);
    end
end
d = D(T1+1, T2+1);

% Backtrack the warping path
i = T1; j = T2; ix = zeros(T1+T2, 1); iy = ix; k = 0;
while i > 0 && j > 0
    k = k + 1; ix(k) = i; iy(k) = j;
    [~, mv] = min([D(i,j), D(i,j+1), D(i+1,j)]);
    switch mv
        case 1, i = i-1; j = j-1;
        case 2, i = i-1;
        case 3, j = j-1;
    end
end
ix = flipud(ix(1:k));
iy = flipud(iy(1:k));
end


function delta = firDelta(cepstra, N)
% Linear regression differencing along the frame axis, with symmetric edge
% padding so the first and last frames are not distorted.

[T, D] = size(cepstra);
delta  = zeros(T, D);
denom  = 2 * sum((1:N).^2);

padded = [repmat(cepstra(1,:), N, 1); cepstra; repmat(cepstra(end,:), N, 1)];

for t = 1:T
    pi_ = t + N;
    s   = zeros(1, D);
    for n = 1:N
        s = s + n * (padded(pi_+n, :) - padded(pi_-n, :));
    end
    delta(t, :) = s / denom;
end
end


function d = dtwNorm(A, B)
% DTW between two feature matrices stored as [frames x coefficients],
% divided by the length of the optimal warping path, so that long and short
% utterances give comparable numbers (defect D1 fix, kept).
if isempty(A) || isempty(B)
    d = inf; return;
end
[raw, ix] = dtwSafe(A.', B.');
d = raw / max(numel(ix), 1);
end


function C = lbgCodebook(X, K, iters)
% Linde-Buzo-Gray vector quantiser design: start from the global centroid,
% split every codeword in two (+/- 1% of the data spread), then refine with
% k-means (nearest-codeword assignment + centroid update). Repeat until K
% codewords. K should be a power of two.
if nargin < 3, iters = 15; end
X = double(X);
K = max(1, min(K, size(X, 1)));
C = mean(X, 1);
e = 0.01 * std(X, 0, 1);
e(e == 0) = 1e-3;
while size(C, 1) < K
    C = [C + e; C - e]; %#ok<AGROW>
    for it = 1:iters
        D2 = sum(X.^2, 2) + sum(C.^2, 2).' - 2 * (X * C.');
        [~, a] = min(D2, [], 2);
        for k = 1:size(C, 1)
            m = (a == k);
            if any(m)
                C(k, :) = mean(X(m, :), 1);
            end
        end
    end
end
C = C(1:min(K, size(C, 1)), :);
end


function d = vqDistortion(X, C)
% Average Euclidean distance from every frame to its nearest codeword.
if isempty(X) || isempty(C)
    d = inf; return;
end
D2 = sum(X.^2, 2) + sum(C.^2, 2).' - 2 * (X * C.');
d  = mean(sqrt(max(min(D2, [], 2), 0)));
end


function m = lowMean(v, k)
v = sort(v(isfinite(v)));
if isempty(v)
    m = inf; return;
end
m = mean(v(1:min(k, numel(v))));
end
