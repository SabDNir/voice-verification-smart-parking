function S = cohortRatio(D, enrolled, cohortSize)
%COHORTRATIO  Cohort-normalised speaker score (log distance ratio).  [Arnob]
%
%   S(:,c) = log( mean of the cohortSize smallest distances to OTHER
%                 enrolled students  /  distance to student c )
%
% D is [numUtterances x numStudents]; enrolled is a logical or index vector
% of the students allowed in the comparison. Columns of students that are
% not enrolled come back as -Inf.
%
% Why a ratio against the nearest others: a raw distance changes with the
% microphone, the room and how loudly someone speaks, and it shifts for
% every student together. Dividing by the distance to the closest
% competing students cancels that common shift (the cohort normalisation of
% Rosenberg et al., 1992). S > 0 means "closer to c than to c's nearest
% rivals"; a genuine user typically scores 0.1-0.4, an impostor below 0.

if islogical(enrolled), enrolled = find(enrolled); end
[nU, N] = size(D);
S = -inf(nU, N);
for c = enrolled(:).'
    others = setdiff(enrolled, c);
    for a = 1:nU
        o = vsUtils('lowmean', D(a, others), cohortSize);
        if isfinite(D(a, c)) && isfinite(o)
            % max(...,1e-9): a recording compared with itself has distance 0
            S(a, c) = log(o / max(D(a, c), 1e-9));
        end
    end
end
end
