%num_loc=96;
%M=round(1e5*rand(num_loc,num_loc));
load ../statecodes


'select input and outputname'
commutedata_filename = 'commutedata'; %output

M=readmatrix("final_commuting_matrix_Oct2023.csv");%input

% %%% create ZEROS - no commuting 
% load ../population.mat
% commutedata_filename = "commutedata_ZEROS.mat";
% M=zeros(size(M))
% M = diag(population);


%%%


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


