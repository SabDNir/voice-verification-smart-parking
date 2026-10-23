function dDTW = speakerDistances(U, Students, uttType)
%SPEAKERDISTANCES  Phrase evidence: "whose roll number / name was said?"  [Arnob]
%
%   dDTW(u, j)  best DTW cost per path step between utterance u and any of
%               student j's own takes of the same phrase (uttType 'roll' or
%               'name'). Small when the SAME words are said - text-dependent
%               evidence. cohortRatio turns it into a score.
%
% The voice (who is speaking) is scored separately by voiceModel('llr').
% U may be a struct array (the utterances of one login); one row per utterance.

if nargin < 3 || isempty(uttType)
    if isfield(U, 'UttType'), uttType = {U.UttType}; else, uttType = {'roll'}; end
end
if ischar(uttType), uttType = repmat({uttType}, 1, numel(U)); end

N    = numel(Students);
nU   = numel(U);
dDTW = inf(nU, N);
for j = 1:N
    for u = 1:nU
        k = find(strcmp({Students(j).Utts.Utt}, uttType{u}));
        for t = k
            dDTW(u, j) = min(dDTW(u, j), ...
                vsUtils('dtwnorm', U(u).Content, double(Students(j).Utts(t).Content)));
        end
    end
end
end
