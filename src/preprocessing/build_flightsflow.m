function build_flightsflow()
%BUILD_FLIGHTSFLOW  Build the air-travel structures from the raw flow matrix.
%
%   build_flightsflow()
%
% Converts data/raw/Matrix-air-flow-sep04.csv (annual air passengers between
% each pair of locations) into the neighbour-list representation used by
% MODEL_FORECAST_RUN, and saves it to data/mobility/flightsflow.mat:
%
%   nlp    neighbour location index for each connection
%   partp  partition of nlp per location
%   P      annual passengers on each connection
%
% The model divides P by 365 to get daily passengers.
%
% Only needed if the mobility structures have to be rebuilt -- the shipped
% .mat file already contains them.
%
% See also BUILD_COMMUTEDATA.

paths = setup_paths();

M = readmatrix(paths.raw_air_flow_matrix);   %input
flights_filename = paths.flightsflow;        %output

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
fprintf('Saved %s\n', flights_filename);

%%% sanity check against M
for idx = 1:5
    i_loc = find(partp(2:end) > idx, 1); % which location this connection belongs to
    j_loc = nlp(idx);
    flow_value = P(idx);
    fprintf('Connection %d: from location %d to location %d, flow = %d\n', idx, i_loc, j_loc, flow_value);
end

end
