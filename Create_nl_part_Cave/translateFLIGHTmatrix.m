%num_loc=96;
%M=round(1e5*rand(num_loc,num_loc));
%load ../statecodes


'select input and outputname'
M=readmatrix("Matrix-air-flow-sep04.csv"); %input
flights_filename = 'flightsflow'; %output

%M(j,i) air passengers between two locationss
%M(i,i) = 0 

M=triu(M); %only the uper matrix, cause it us symmetrical
num_loc=size(M,1);
threshold=0;%threshold for air traveller flow
nlp=zeros(1e3,1);%neighborlist
P=zeros(1e3,1);% symmetric

partp=zeros(num_loc+1,1);%partition for nighborlist for each location
partp(1)=1;
cnt=0;
for i=1:num_loc
    for j=1:num_loc
        if (M(j,i)>threshold)
            cnt=cnt+1;
            nlp(cnt)=j;
            P(cnt)=M(j,i);
        end
    end
    partp(i+1)=cnt+1;
end
nlp=nlp(1:cnt);
P=P(1:cnt);

save(flights_filename,'nlp', 'partp', 'P')
clear



%%% check with the M
for idx = 1:5
    i_loc = find(partp(2:end) > idx, 1); % which location this connection belongs to
    j_loc = nlp(idx);
    flow_value = P(idx);
    fprintf('Connection %d: from location %d to location %d, flow = %d\n', idx, i_loc, j_loc, flow_value);
end

