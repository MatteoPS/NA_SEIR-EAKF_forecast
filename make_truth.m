function make_truth(truth_nick)

% truth nick example:
% "t10_om_CA", "t03_wt_CA"...
% see Truth-descriprion.xlxs



load statecodes
load population.mat
load parafit_vars.mat alphamaps betamap
load flightsflow.mat
P=P/365; %daily number of passengers

% pars from truth_nick
nickparts = split(truth_nick, '_');
strain = nickparts{2};
seed_code = nickparts{3};
truth_id = nickparts{1};


%truth OEV par (different form the one used in the model)
truth_OEV_denom=150;
truth_OEV_base=7;


num_times=365; % simulation lenght

truth_filename = strjoin(['Truths/truth_' truth_nick '.mat'],'');

seed_options = table(...
    ["NY";"WA";"CA";"TX";"GA";"ON";"MX"], ...
    ["New York"; "Washington"; "California"; "Texas"; "Georgia"; "Ontario"; "Distrito Federal"], ...
    'VariableNames', {'code', 'name'});


commuting = "network";   %trues have always the commuting network and flights

commuting = "patch"
flight = "nf"
noise = "off"
if commuting == "network"
    load commutedata.mat
elseif commuting == "patch"
    load commutedata_ZEROS.mat
else
    errror("commuting: 'network' or 'patch'?")
end


if ~ismember(strain, ["ls", "lo", "me", "hi", "hs"])
    error('strain: "ls", "lo", "me", "hi", "hs"')
end

% fix true value here:
if strain == "ls"
    truth_beta_val = 0.8;
elseif strain == "lo"
    truth_beta_val = 1;
elseif strain == "me"
    truth_beta_val = 2;
elseif strain == "hi"
    truth_beta_val = 3;
elseif strain == "hs"
    truth_beta_val = 4;
end

if ~ismember(seed_code, seed_options.code)
    error("seed must be one of: %s", strjoin(seed_options.code, ", "))
end

%set non strain-dependet true parameters
truth_mu=0.33;
truth_theta=0.12;
truth_Z=3.5;
truth_D=3.5;
truth_alpha_ca = 0.25;
truth_alpha_us = 0.25;
truth_alpha_mx = 0.25;


%%%%%%%%%%%%%%%%%%%
num_loc=size(part,1)-1;
num_mp=size(nl,1);


%initialize model

%Setting manually, S is the pop and the rest are 0

if strain == "ls" || strain == "lo"
    S=ceil(C*0.92);
elseif strain == "me"
    S=ceil(C*0.75);
elseif strain == "hi"|| strain == "hs"
    S=ceil(C*0.5);
end

E=zeros(size(S));
Ir=zeros(size(S));
Iu=zeros(size(S));

%initialize parameters


%Z,D,mu,theta,alpha1,alpha2,...,alpha3142,beta1,...,beta3142
%paramin=[Zlow;Dlow;mulow;thetalow;ones(num_loc,1)*alphalow;ones(num_loc,1)*betalow];
%paramax=[Zup;Dup;muup;thetaup;ones(num_loc,1)*alphaup;ones(num_loc,1)*betaup];

CAid = statecodes.Var1(statecodes.Var3 == "CA");
USid = statecodes.Var1(statecodes.Var3 == "US");
MXid = statecodes.Var1(statecodes.Var3 == "MX");


para(1)=truth_Z; %Z
para(2)=truth_D; %D
para(3)=truth_mu; %mu
para(4)=truth_theta; %teta


%alpha
para(alphamaps(CAid))=truth_alpha_ca; %set canada alpha
para(alphamaps(USid))=truth_alpha_us; %set USA alpha
para(alphamaps(MXid))=truth_alpha_mx; %set Mexico alpha

%beta
para(betamap) = truth_beta_val;



%%%%%%%%%% SEED THRUTH

%random minimal seed everywhere
%E(:,1)=round(abs(randn(size(Iu(:,1)))).*C(:,1)./10000);

% Iu(:,1)=round(abs(randn(size(Iu(:,1)))).*C(:,1)./10000);
% for l=1:num_loc
%     for j=part(l):part(l+1)-1
%         Ir(j,1)=round(Iu(j,1)*(para(alphamaps(l)))); %multiplying Iu by alpha to seed Ir
%     end
% end

% adding more cases in seed location
seed_name = seed_options.name(seed_options.code == seed_code);
seed_l = statecodes.Var1(statecodes.Var2 == seed_name);
for j=part(seed_l):part(seed_l+1)-1
    E(j,1)=ceil(C(j,1)./1000);
    %Iu(j,1)=ceil(C(j,1)./1000); %seeding the undetected in all the subpop of seed_loc
    %Ir(j,1)=ceil(Iu(j,1)*(para(alphamaps(seed_l)))); %multiplying Iu by alpha to get Ir
end




dailyIr_post_rec=zeros(num_loc,num_times);%posterior reported infection
dailyIu_post_rec=zeros(num_loc,num_times);%posterior unreported infection
%initialize poseteriors (percentage of population)
S_post=zeros(num_loc,num_times);
E_post=zeros(num_loc,num_times);
Ir_post=zeros(num_loc,num_times);
Iu_post=zeros(num_loc,num_times);
%initialize cumulative reported and unreported infections
cumu_dailyIr_post=zeros(num_mp);
cumu_dailyIu_post=zeros(num_mp);

%%%%%%%%%%%%%%%%%%%%%%%

% variables for flight flow correcction
truth_delta_all_rec=zeros(num_times,length(P));

% Pre-compute location partitioning indices
loc_ranges = cell(length(part)-1, 1);
for i = 1:length(part)-1
    loc_ranges{i} = part(i):part(i+1)-1;
end

% Build location index vector (maps each metapopulation index to location)
location_indices = zeros(num_mp, 1);
for i = 1:length(part)-1
    location_indices(loc_ranges{i}) = i;
end

% Pre-compute passenger connection matrices
num_locs = length(part)-1;
num_connections = length(P);

% Source and destination location indices for each connection
source_locs = zeros(num_connections, 1);
dest_locs = zeros(num_connections, 1);
conn_idx = 1;

for i = 1:length(partp)-1
    passenger_idx_range = partp(i):partp(i+1)-1;
    for p_idx = passenger_idx_range
        j = nlp(p_idx);
        source_locs(conn_idx) = i;
        dest_locs(conn_idx) = j;
        conn_idx = conn_idx + 1;
    end
end

% Store first metapop index for each location (for fast updates)
loc_first_idx = part(1:end-1);


for t=1:num_times

    %integrate forward one step
    [S,E,Ir,Iu,dailyIr_temp,dailyIu_temp]=integrate_model(nl,part,C,Cave,S,E,Ir,Iu,para,betamap,alphamaps);

    % VECTORIZED PASSENGER FLOW CALCULATION

    % Aggregate Ir and Iu by location using accumarray
    Ir_sums = accumarray(location_indices, Ir, [num_locs, 1]);
    Iu_sums = accumarray(location_indices, Iu, [num_locs, 1]);

    % Rates for i→j direction
    rates_i_to_j = P .* Iu_sums(source_locs) ./ ...
        (population(source_locs) - Ir_sums(source_locs));

    % Rates for j→i direction
    rates_j_to_i = P .* Iu_sums(dest_locs) ./ ...
        (population(dest_locs) - Ir_sums(dest_locs));

    % Check for negative rates
    neg_mask_ij = rates_i_to_j < 0;
    neg_mask_ji = rates_j_to_i < 0;

    if any(neg_mask_ij | neg_mask_ji)
        fprintf('NEGATIVE RATES DETECTED at t=%d %s\n ', t, truth_nick);
        fprintf('Number of negative i→j rates: %d\n', sum(neg_mask_ij));
        fprintf('Number of negative j→i rates: %d\n', sum(neg_mask_ji));

        % Set negative rates to zero
        rates_i_to_j(neg_mask_ij) = 0;
        rates_j_to_i(neg_mask_ji) = 0;
    end

    % Generate all Poisson samples (vectorized)
    pois_i_to_j = poissrnd(rates_i_to_j);
    pois_j_to_i = poissrnd(rates_j_to_i);

    % Compute net flows
    net_deltas = pois_i_to_j - pois_j_to_i;

    % Store for recording
    truth_delta_all_rec(t, :) = net_deltas;

    % Apply updates using accumarray:
    %B = accumarray(ind,data) sums groups of data by accumulating
    % elements of a vector data according to the groups specified in ind.

    % Changes to Iu for destination locations (gains)
    delta_Iu_dest = accumarray(dest_locs, net_deltas, [num_locs, 1]);
    % Changes to Iu for source locations (losses)
    delta_Iu_src = accumarray(source_locs, -net_deltas, [num_locs, 1]);
    %

    if flight ~= "nf"
        % Apply to first index of each location
        Iu(loc_first_idx) = max(Iu(loc_first_idx) + delta_Iu_dest, 0);
        Iu(loc_first_idx) = max(Iu(loc_first_idx) + delta_Iu_src, 0);

        % Same for S (opposite sign)
        S(loc_first_idx) = max(S(loc_first_idx) - delta_Iu_dest, 0);
        S(loc_first_idx) = max(S(loc_first_idx) - delta_Iu_src, 0);

        % Update daily tracking
        dailyIu_temp(loc_first_idx) = max(dailyIu_temp(loc_first_idx) + delta_Iu_dest, 0);
        dailyIu_temp(loc_first_idx) = max(dailyIu_temp(loc_first_idx) + delta_Iu_src, 0);
    end
    %%%%%%%%%%%%%%%%%%%%%%

    cumu_dailyIr_post=cumu_dailyIr_post+dailyIr_temp;
    cumu_dailyIu_post=cumu_dailyIu_post+dailyIu_temp;

    %%%%%%%%save statevariables
    for i=1:num_loc
        S_post(i,t)=sum(S(part(i):part(i+1)-1))./population(i);
        S_post_abs(i,t)=sum(S(part(i):part(i+1)-1));
        E_post(i,t)=sum(E(part(i):part(i+1)-1))./population(i);
        Ir_post(i,t)=sum(Ir(part(i):part(i+1)-1))./population(i);
        Iu_post(i,t)= sum(Iu(part(i):part(i+1)-1))./population(i);
        dailyIr_post_rec(i,t)=sum(dailyIr_temp(part(i):part(i+1)-1));
        dailyIu_post_rec(i,t)=sum(dailyIu_temp(part(i):part(i+1)-1));
        cumu_dailyIr_post_rec(i,t)=sum(cumu_dailyIr_post(part(i):part(i+1)-1)); %real numbers, not percentage
        cumu_dailyIu_post_rec(i,t)=sum(cumu_dailyIu_post(part(i):part(i+1)-1)); %real numbers, not percentage

        % Add noise to dailyIr

        obs_ave=mean(dailyIr_post_rec(i,max(1,t-6):t));
        truth_OEV_case(i,t)= max(truth_OEV_base,(obs_ave^2)/truth_OEV_denom);
        noisy_dailyIr(i,t) = max(0,ceil(dailyIr_post_rec(i,t)+randn*sqrt(truth_OEV_case(i,t))));
        if noise == "off"
            noisy_dailyIr(i,t)=dailyIr_post_rec(i,t);
        end

        % if true_cases > 0
        %     % Negative binomial: mean = true_cases, variance = true_cases + true_cases^2/k
        %     % This gives variance proportional to mean, but sublinear
        %     k=truth_disp_par;
        %     noisy_dailyIr(i,t) = nbinrnd(k, k/(k+true_cases));
        % else
        %     noisy_dailyIr(i,t) = 0;
        % end
        %

    end

    %%%%%%%%save posterior statevariables totals
    totalS(t,:)=sum(S);
    totalE(t,:)=sum(E);
    totalIr(t,:)=sum(Ir);
    totalIu(t,:)=sum(Iu);

    %%% trues


    truth_tracktrueS(:,t)=S;
    truth_tracktrueE(:,t)=E;
    truth_tracktrueIr(:,t)=Ir;
    truth_tracktrueIu(:,t)=Iu;
    %truth_tracktrueR(:,t)=R;

end


% adding "truth_" for saving and retrieving
truth_totalS=totalS;
truth_totalE=totalE;
truth_totalIr=totalIr;
truth_totalIu=totalIu;


truth_para_post=para;
truth_S_post=S_post;
truth_dailyIr_post_rec=dailyIr_post_rec;
truth_dailyIu_post_rec=dailyIu_post_rec;
truth_noisy_dailyIr_rec=noisy_dailyIr;




truth_dailyIr_post_cumu=cumu_dailyIr_post_rec./population;
truth_dailyIu_post_cumu=cumu_dailyIu_post_rec./population;


truth_srain=strain;
truth_seed_code=seed_code;
truth_commuting=commuting;


%Find variables that start with "truth_"
truth_vars = who('truth_*');

save(truth_filename, truth_vars{:});

Plotting_truth(truth_filename)
