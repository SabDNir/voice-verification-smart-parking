function varargout = voiceModel(op, varargin)
%VOICEMODEL  GMM-UBM voice models (text-independent speaker verification).  [Arnob]
%
%   F   = voiceModel('features', VQ)            [c1..c12, delta] of the speech frames
%   ubm = voiceModel('trainubm', X, cfg)        Universal Background Model from everyone
%   mu  = voiceModel('adapt', X, ubm, r)        MAP-adapted means of one student
%   s   = voiceModel('llr', X, MU, ubm)         average log-likelihood ratio per frame,
%                                               one value per student (MU is K x D x N)
%
% WHY THIS REPLACED THE 32-WORD VQ CODEBOOK (v3.2)
%   Live tests on 27 Sep 2026 (same microphone as the database, 12 genuine
%   logins, 6 impersonations) showed the VQ codebook put the true speaker
%   first in only 2 of 12 genuine logins. With the GMM-UBM below, trained on
%   exactly the same frames, the true speaker was first in 11-12 of 12.
%
% METHOD (Reynolds, Quatieri and Dunn, "Speaker verification using adapted
% Gaussian mixture models", Digital Signal Processing 10, 2000)
%   1. UBM: one diagonal-covariance GMM (cfg.NumMixtures components) fitted by
%      EM to the speech frames of ALL enrolled students. It models "a voice
%      in general" in this room, with this microphone and this language.
%   2. Each student's model = the UBM with its means pulled towards that
%      student's frames (MAP adaptation, relevance factor r):
%          mu_k = a_k * E_k[x] + (1 - a_k) * mu_k(UBM),   a_k = n_k / (n_k + r)
%      Components the student never used stay at the UBM, so a few seconds of
%      speech is enough and the model cannot over-fit.
%   3. Score of a test utterance X against student j:
%          LLR_j = mean over frames of  log p(x | student j) - log p(x | UBM)
%      > 0 means "sounds more like j than like people in general". The UBM
%      term cancels most of the channel and phrase effects that hurt the
%      VQ distance.

switch lower(char(op))
    case 'features'
        VQ = double(varargin{1});
        if size(VQ, 1) < 5
            varargout = {zeros(0, 2 * size(VQ, 2))}; return;
        end
        varargout = {[VQ, vsUtils('firdelta', VQ, 2)]};
    case 'trainubm'
        varargout = {trainUBM(varargin{:})};
    case 'adapt'
        varargout = {mapAdapt(varargin{:})};
    case 'llr'
        varargout = {llrScores(varargin{:})};
    case 'loglik'
        varargout = {frameLogLik(varargin{:})};
    otherwise
        error('ParkingSecuritySystem:BadVoiceOp', 'Unknown voiceModel operation "%s".', char(op));
end
end


function ubm = trainUBM(X, cfg)
X = double(X);
if size(X, 1) > cfg.UBMMaxFrames                 % uniform thinning keeps it fast
    X = X(round(linspace(1, size(X, 1), cfg.UBMMaxFrames)), :);
end
K  = cfg.NumMixtures;
N  = size(X, 1);
floorVar = 1e-3 * var(X, 0, 1);
mu = vsUtils('lbg', X, K, cfg.LBGIterations);     % deterministic start
K  = size(mu, 1);
v  = repmat(var(X, 0, 1), K, 1);
w  = ones(K, 1) / K;
for it = 1:cfg.EMIterations
    L = logJoint(X, w, mu, v);
    P = exp(L - max(L, [], 2));
    P = P ./ sum(P, 2);
    n = sum(P, 1).' + 1e-10;
    w  = n / N;
    mu = (P.' * X) ./ n;
    v  = max((P.' * (X.^2)) ./ n - mu.^2, floorVar);
end
ubm = struct('w', w, 'mu', mu, 'var', v, 'K', K, 'NumFrames', N);
end


function mu = mapAdapt(X, ubm, r)
X = double(X);
L = logJoint(X, ubm.w, ubm.mu, ubm.var);
P = exp(L - max(L, [], 2));
P = P ./ sum(P, 2);
n  = sum(P, 1).';
Ex = (P.' * X) ./ max(n, 1e-10);
a  = n ./ (n + r);
mu = a .* Ex + (1 - a) .* ubm.mu;
end


function s = llrScores(X, MU, ubm)
X = double(X);
N = size(MU, 3);
s = -inf(1, N);
if size(X, 1) < 5, return; end
lu = frameLogLik(X, ubm.w, ubm.mu, ubm.var);
for j = 1:N
    lj   = frameLogLik(X, ubm.w, double(MU(:, :, j)), ubm.var);
    s(j) = mean(lj - lu);
end
end


function ll = frameLogLik(X, w, mu, v)
L  = logJoint(X, w, mu, v);
m  = max(L, [], 2);
ll = m + log(sum(exp(L - m), 2));
end


function L = logJoint(X, w, mu, v)
% log( w_k N(x | mu_k, diag(v_k)) ) for every frame (rows) and component (columns)
iv = 1 ./ v;
L  = log(w(:)).' - 0.5 * sum(log(2 * pi * v), 2).' ...
     - 0.5 * ((X.^2) * iv.' - 2 * X * (mu .* iv).' + sum(mu.^2 .* iv, 2).');
end
