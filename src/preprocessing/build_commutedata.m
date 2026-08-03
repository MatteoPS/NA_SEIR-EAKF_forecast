function build_commutedata(zero_commuting)
%BUILD_COMMUTEDATA  Build the commuting network structures from the raw matrix.
%
%   build_commutedata()        % -> data/mobility/commutedata.mat
%   build_commutedata(true)    % -> data/mobility/commutedata_ZEROS.mat
%
% Converts data/raw/final_commuting_matrix_Oct2023.csv into the neighbour-list
% representation used by INTEGRATE_MODEL:
%
%   nl    neighbour location index for each metapopulation unit
%   part  partition of nl per location
%   C     commuting population (not necessarily symmetric)
%   Cave  average commuting population (symmetric)
%
% Pass true to build the no-commuting ("patch") variant instead, where every
% location keeps its whole population at home.
%
% Only needed if the mobility structures have to be rebuilt -- the shipped
% .mat files already contain them.
%
% See also BUILD_FLIGHTSFLOW.

if nargin < 1, zero_commuting = false; end

paths = setup_paths();

M = readmatrix(paths.raw_commuting_matrix);   %input

if zero_commuting
    % no commuting: everybody stays in their own location
    load(paths.population);                   % -> population
    M = diag(population);
    commutedata_filename = paths.commutedata_zeros;
else
    commutedata_filename = paths.commutedata;
end

%M is the mobility matrix
%M(j,i) is the population living in location i traveling to location j
%M(i,i) is the population living in location i staying in location i
%M(i,i) is the total population in location i minus all outgoing population
Commute=M;
num_loc=size(Commute,1);
threshold=0.1;%threshold for inter-county commuting (small positive)
countypop=sum(M,1);
nl=zeros(1e3,1);%neighborlist
C=zeros(1e3,1);%mobility, not necessarily symmetric
Cave=zeros(1e3,1);%average mobility, symmetric
part=zeros(num_loc+1,1);%partition for nighborlist for each location
part(1)=1;
cnt=0;
for i=1:num_loc
    %check location i
    if Commute(i,i)>=0%same location, population - all outgoing mobility
        %the same location i always appears as the first location in the neighborlist
        cnt=cnt+1;
        nl(cnt)=i;
        C(cnt)=Commute(i,i);
        Cave(cnt)=Commute(i,i);
        countypop(i)=sum(Commute(:,i));
    end
    %other locations
    for j=1:num_loc
        if (Commute(j,i)>=threshold)&&(Commute(i,j)>=threshold)&&(j~=i)
            cnt=cnt+1;
            nl(cnt)=j;
            C(cnt)=Commute(j,i);
            %Cave(cnt)=round((Commute(j,i)+Commute(i,j))/2);
            Cave(cnt)=(Commute(j,i)+Commute(i,j))/2;
            
        end
    end
    part(i+1)=cnt+1;
end
nl=nl(1:cnt);
C=C(1:cnt);
Cave=Cave(1:cnt);
%double check the popoluation add up to the total population
population=countypop;
for l=1:num_loc
    if sum(C(part(l):part(l+1)-1))~=population(l)
        C(part(l))=population(l)-sum(C(part(l)+1:part(l+1)-1));
    end
    if sum(Cave(part(l):part(l+1)-1))~=population(l)
        Cave(part(l))=population(l)-sum(Cave(part(l)+1:part(l+1)-1));
    end
end

save(commutedata_filename,'nl', 'part', 'C', 'Cave')
fprintf('Saved %s\n', commutedata_filename);

end


