function MODEL_RUN(run_id,mmdd)

%reproductive number R
%Rt ≡ βD[α + (1 − α)μ]

% getting run info from description tables
truths_description=readtable("Truths-description.xlsx");
% Get nicknames from runs-description
opts = detectImportOptions("Runs-description.xlsx");
opts.DataRange = 'A2'; % Start reading from A2
runs_description = readtable("Runs-description.xlsx", opts);
clear opts

idx = strcmp(runs_description.RunID, num2str(run_id));
nickname  = runs_description.nickname{idx};
truth_id  = runs_description.TruthID{idx};
strain    = runs_description.Strain{idx};
seed_loc  = runs_description.Seed_loc{idx};
flights   = runs_description.Flights{idx};
Commuting = runs_description.Commuting{idx};
Stochastic = runs_description.Stochastic{idx};

truth_nick = truths_description.Truth_nickname{strcmp(truths_description.TruthID, truth_id)};


num_ens=150;



%%%%%%%%%%%%%%%%%loading data
load flightsflow.mat
P=P/365; %daily number of passengers

truth_filename = "Truths/truth_" + truth_nick + ".mat";
file_info = dir(truth_filename);
if ~isempty(file_info)
    load(fullfile('Truths', file_info(1).name));
    num_times=365;
    dailyincidence=truth_noisy_dailyIr_rec(:,1:num_times);
elseif truth_id=='tr00'
    num_times=437; %from January 20, 2020 to  March 31, 2021
    load dailyincidence_real.csv
    dailyincidence=dailyincidence_real(:,1:num_times);
else
    error('No file found matching: %s', truth_filename);
end

%load commuting data - ZEROS has no commuting
if Commuting == "n"
    load commutedata.mat
elseif Commuting == "p"
    load commutedata_ZEROS.mat
else
    "'n' for network or 'p' for patch"
end

load statecodes.mat
load population.mat
load parafit_vars.mat
load fix_rand_matrix.mat
load fix_para.mat
load fix_randi_reprobe.mat

%%%%%%% select today for figures names
%mmdd=datestr(datetime('now'), 'mmdd');
all_file_name=strjoin([ "Model_Runs/" mmdd "_" nickname ".mat"],'');

%inflation in EAKF
%%%%% OEV settings, OEV_case(l,t)=max(OEV_base,obs_ave^OEV_exp);


if Stochastic == "y"
    lambda=1.003;
    lambda_beta=lambda;
    lambda_obs=lambda;
    OEV_denom=200;
    OEV_base=5;


elseif Stochastic == "n"
    lambda=1.003;
    lambda_beta=lambda;
    lambda_obs=lambda;
    OEV_denom=100;
    OEV_base=5;

else
    error("Stochastic needs to be either 'y' or 'n' for deterministic");
end



%inflation factor for the values of out-of-bound para in checkbound_para.m
flact_checkpara=0;

%inflate observed variable, yes/no
inflate_obs = "yes";
%inflate all the other state variables, yes/no
inflate_sv = "no";
%%%%%%%%%%%%%%%%%%%%% reprobe parameters
doreprobe= "yes";   % yes/no if you're reprobinge -- I reinitialize alpha and beta, not reprobe
reprobe_percent=2;  % what percent of the ensemble to reprobe
reprobe_t=7;        % how often to reprobe (days)
reprobeS= "no";     % yes/no if you're reprobing State Variables

% create the fix random matrix for deterninistic - do redo if
% change reprobe parameters abovea
%fix_randi_lenght=ceil(num_times/reprobe_t)
%fix_randi_heigh=round(num_ens*reprobe_percent/100)
%fix_randi_reprobe=randi([1 num_ens],fix_randi_heigh,fix_randi_lenght);


num_loc=size(part,1)-1;
num_mp=size(nl,1);


%%%% forecast settings
forecast_start_after_week = 1;
forecast_stop_after_week = floor(num_times/7)-1;

forecast_weeks = forecast_start_after_week:forecast_stop_after_week;

week_starts_days = forecast_weeks*7;

%forcasting week check
if (forecast_stop_after_week * 7) > num_times
    error('cannot forecast up to week %d, incidence data stop at day %d', forecast_stop_after_week, num_times);
end

%forecast initializations

forecast_struct = struct( 'week_counter', {}, 'start_day', {});
file_name_fore = "Forecasts/" + "fore_"+ nickname;
forecast_num = 0;

%smooth the data: 7 day moving average
obs_case=dailyincidence;
for l=1:num_loc
    for t=1:num_times
        if (t+3)<=num_times
            obs_case(l,t)=(mean(dailyincidence(l,max(1,t-3):min(t+3,num_times))));
        else
            obs_case(l,t)=(mean(dailyincidence(l,max(1,num_times-6):num_times)));
        end
    end
end



%set OEV, observation error variance
OEV_case=zeros(size(dailyincidence));
for l=1:num_loc
    for t=1:num_times
        obs_ave=mean(dailyincidence(l,max(1,t-6):t));

        OEV_case(l,t)=max(OEV_base,(obs_ave^2)/OEV_denom);
    end
end
%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%initialize model state variable
% Determine random matrix source
if Stochastic == "y"
    rand_vals = rand(num_mp, num_ens);
elseif Stochastic == "n"
    rand_vals = fix_rand_matrix(1:num_mp, 1:num_ens);
else
    error("Stochastic needs to be either 'y' or 'n' for deterministic");
end

% Determine base value based on strain
switch strain
    case {"ls", "lo", ""}
        base_val = 0.70;
    case "me"
        base_val = 0.55;
    case {"hi", "hs"}
        base_val = 0.40;
    otherwise
        % Handle unexpected strain
        error("'strain' name not recognise, check run_description");
end

% state variable initialization:
S = C .* (base_val + 0.30 * rand_vals);
Ir=zeros(size(S));
E=zeros(size(S));
Iu = zeros(size(S)); %each loacation will get one Iu/100K per day


if Stochastic == "y"
    [S,E,Ir,Iu]=checkbound(S,E,Ir,Iu,C);
    %initialize parameter
    [para]=initialize_para(num_loc,num_ens,parafit,alphamaps,betamap);
    %out-of-bound Z,D,mu and theta are resampled across their ranges
    for i=1:size(para,1)-length(alphamaps)-length(betamap)
        para(i,para(i,:)<paramin(i))=random('uniform', paramin(i), paramax(i), size(para(i,para(i,:)<paramin(i)))); % selecting random values between the bound for each ensamble out
        para(i,para(i,:)>paramax(i))=random('uniform', paramin(i), paramax(i), size(para(i,para(i,:)>paramax(i))));
    end

elseif Stochastic == "n"
    para=fix_para;
    t_reprobe=0; %initialize counter for reprobing after EAKF
else
    error("Stochastic needs to be either 'y' or 'n' for deterministic")
end





% if contains(nickname, "synthOLD")
%     seed max of 9 exposed or a 1/50000 of the pop exposed in each location
     E= max(9,round(abs(rand(size(S))).*C./50000));
%     [S,E,Ir,Iu]=checkbound(S,E,Ir,Iu,C);
% end
% 


para_ori=para; %used to re-initialize alpha and beta

%%%%%%%%%%%%%%%%%%%%% reprobe parameters

reprobe_whichpara=cat(1,alphamaps,betamap);  % reprobe only the pars I am estimating
parastd=std(para,0,2);%get ensemble spread of parameters


%%%%%%%%%%%%%%%%%%%%% inizialize empty variables

dailyIr_prior_rec=zeros(num_loc,num_ens,num_times);%prior reported infection
dailyIu_prior_rec=zeros(num_loc,num_ens,num_times);%prior unreported infection

obs_var_rec=zeros(num_loc,num_times);
prior_var_rec=zeros(num_loc,num_times);
prior_mean_rec=zeros(num_loc,num_times);
post_var_rec=zeros(num_loc,num_times);
post_mean_rec=zeros(num_loc,num_times);
alpha_rec=zeros(num_loc,num_times);


dy_rec=zeros(num_loc,num_ens,num_times); %Kalman gain dy
dx_alpha_rec=zeros(num_loc,num_ens,num_times); %Kalman gain dx alpha
dx_beta_rec=zeros(num_loc,num_ens,num_times); %Kalman gain dx beta
%dx_E_rec=zeros(num_loc,num_ens,num_times);
%dx_Ir_rec=zeros(num_loc,num_ens,num_times);
%dx_Iu_rec=zeros(num_loc,num_ens,num_times);
%dx_dailyIr_prior_rec=zeros(num_loc,num_ens,num_times);
%dx_dailyIu_prior_rec=zeros(num_loc,num_ens,num_times);




%initialize poseteriors (ends with rec=counts, ends with post=perc)
S_post=zeros(num_loc,num_times,num_ens);
%S_rec=zeros(num_loc,num_times,num_ens);
%E_post=zeros(num_loc,num_times,num_ens);
%E_rec=zeros(num_loc,num_times,num_ens);
%Ir_post=zeros(num_loc,num_times,num_ens);
%Ir_rec=zeros(num_loc,num_times,num_ens);
%Iu_post=zeros(num_loc,num_times,num_ens);
%Iu_rec=zeros(num_loc,num_times,num_ens);
dailyIr_post_rec=zeros(num_loc,num_ens,num_times);
cumu_dailyIr_post_rec=zeros(num_loc,num_times,num_ens);
dailyIu_post_rec=zeros(num_loc,num_ens,num_times);
cumu_dailyIu_post_rec=zeros(num_loc,num_times,num_ens);


%initialize stavariables for yesterday checkbound, used when t>1
S_yesterday=zeros(num_mp,num_ens);
E_yesterday=zeros(num_mp,num_ens);
Ir_yesterday=zeros(num_mp,num_ens);
Iu_yesterday=zeros(num_mp,num_ens);


%initialize cumulative reported and unreported infections
cumu_dailyIr_post=zeros(num_mp,num_ens);
cumu_dailyIu_post=zeros(num_mp,num_ens);

%save para post
num_para=size(para,1);
para_post=zeros(num_para,num_ens,num_times);%posterior parameters


%%%%%%%%%%%%%%%%%%%%%%%
% variables for flight flow correcctopn
%delta_all_rec=zeros(num_times,num_ens,length(P));

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
    % if ~contains(nickname, "synthOLD")
    %     Iu=Iu+C/100000;    %SEEDING 1Iu/100k/day per location per day
    % end
    Iu=Iu+C/100000;    %SEEDING 1Iu/100k/day per location per day
    dailyIr_prior = zeros(num_mp, num_ens);
    dailyIu_prior = zeros(num_mp, num_ens);
    %delta_all_rec(t,:,:) = 0; % Pre-allocate

    for k=1:num_ens
        if Stochastic == "y"
            [S(:,k), E(:,k), Ir(:,k), Iu(:,k), dailyIr_temp, dailyIu_temp] = integrate_model(nl, part, C, Cave, S(:,k), E(:,k), Ir(:,k), Iu(:,k), para(:,k), betamap, alphamaps);
        elseif Stochastic == "n"
            [S(:,k), E(:,k), Ir(:,k), Iu(:,k), dailyIr_temp, dailyIu_temp] = integrate_model_nopois(nl, part, C, Cave, S(:,k), E(:,k), Ir(:,k), Iu(:,k), para(:,k), betamap, alphamaps);
        else
            error("Stochastic needs to be either 'y' or 'n' for deterministic")
        end
        dailyIr_prior(:,k) = dailyIr_temp;
        dailyIu_prior(:,k) = dailyIu_temp;

        if flights == "f"
            % VECTORIZED PASSENGER FLOW CALCULATION

            % Aggregate Ir and Iu by location using accumarray
            Ir_sums = accumarray(location_indices, Ir(:,k), [num_locs, 1]);
            Iu_sums = accumarray(location_indices, Iu(:,k), [num_locs, 1]);

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
                fprintf('NEGATIVE RATES DETECTED at t=%d, k=%d\n', t, k);
                fprintf('Number of negative i→j rates: %d\n', sum(neg_mask_ij));
                fprintf('Number of negative j→i rates: %d\n', sum(neg_mask_ji));

                % Set negative rates to zero
                rates_i_to_j(neg_mask_ij) = 0;
                rates_j_to_i(neg_mask_ji) = 0;
            end
            if Stochastic == "y"
                % Generate all Poisson samples (vectorized)
                rates_i_to_j = poissrnd(rates_i_to_j);
                rates_j_to_i = poissrnd(rates_j_to_i);
            end
            % Compute net flows
            net_deltas = rates_i_to_j - rates_j_to_i;

            % Store for recording
            %delta_all_rec(t, k, :) = net_deltas;

            % Apply updates using accumarray:
            %B = accumarray(ind,data) sums groups of data by accumulating
            % elements of a vector data according to the groups specified in ind.

            % Changes to Iu for destination locations (gains)
            delta_Iu_dest = accumarray(dest_locs, net_deltas, [num_locs, 1]);
            % Changes to Iu for source locations (losses)
            delta_Iu_src = accumarray(source_locs, -net_deltas, [num_locs, 1]);

            % Apply to first index of each location
            Iu(loc_first_idx, k) = max(Iu(loc_first_idx, k) + delta_Iu_dest, 0);
            Iu(loc_first_idx, k) = max(Iu(loc_first_idx, k) + delta_Iu_src, 0);

            % Same for S (opposite sign)
            S(loc_first_idx, k) = max(S(loc_first_idx, k) - delta_Iu_dest, 0);
            S(loc_first_idx, k) = max(S(loc_first_idx, k) - delta_Iu_src, 0);

            % Update daily tracking
            dailyIu_prior(loc_first_idx, k) = max(dailyIu_prior(loc_first_idx, k) + delta_Iu_dest, 0);
            dailyIu_prior(loc_first_idx, k) = max(dailyIu_prior(loc_first_idx, k) + delta_Iu_src, 0);
        end
    end

    %%%%%% inflate observed
    if inflate_obs == "yes"
        dailyIr_prior=max(0,mean(dailyIr_prior,2)*ones(1,num_ens)+lambda_obs*(dailyIr_prior-mean(dailyIr_prior,2)*ones(1,num_ens)));
    end
    if inflate_sv == "yes"
        dailyIu_prior=mean(dailyIu_prior,2)*ones(1,num_ens)+lambda*(dailyIu_prior-mean(dailyIu_prior,2)*ones(1,num_ens));
        S=mean(S,2)*ones(1,num_ens)+lambda*(S-mean(S,2)*ones(1,num_ens));
        E=mean(E,2)*ones(1,num_ens)+lambda*(E-mean(E,2)*ones(1,num_ens));
        Ir=mean(Ir,2)*ones(1,num_ens)+lambda*(Ir-mean(Ir,2)*ones(1,num_ens));
        Iu=mean(Iu,2)*ones(1,num_ens)+lambda*(Iu-mean(Iu,2)*ones(1,num_ens));
    end

    for i=1:num_loc
        for j=1:num_ens
            dailyIr_prior_rec(i,j,t)=sum(dailyIr_prior(part(i):part(i+1)-1,j));
            dailyIu_prior_rec(i,j,t)=sum(dailyIu_prior(part(i):part(i+1)-1,j));
        end
    end


    %%  EAKF  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % starts to assimilate after the first week
    if t>=7

        obs_ens=dailyIr_prior_rec(:,:,t);
        for l=1:num_loc
            %Get the variance of the ensemble
            obs_var = OEV_case(l,t);
            obs_var_rec(l,t)=obs_var;

            prior_var = var(obs_ens(l,:));
            post_var = prior_var*obs_var/(prior_var+obs_var);

            if prior_var==0 %if degenerate assings low number > zero
                post_var=1e-3;
                prior_var=1e-3;
            end

            prior_mean = mean(obs_ens(l,:));
            post_mean = post_var*(prior_mean/prior_var + obs_case(l,t)/obs_var);


            prior_var_rec(l,t)=prior_var;
            prior_mean_rec(l,t)=prior_mean;
            post_var_rec(l,t)=post_var;
            post_mean_rec(l,t)=post_mean;


            %%%% Compute alpha and adjust distribution to conform to posterior moments
            alpha = (obs_var/(obs_var+prior_var)).^0.5;
            alpha_rec(l,t)=alpha;
            dy = post_mean + alpha*(obs_ens(l,:)-prior_mean)-obs_ens(l,:);
            dy_rec(l,:,t)=dy'; %save Kalman gain for plotting

            %Loop over each state variable (connected to location l)
            %adjust related metapopulation
            neighbors=part(l):part(l+1)-1;%metapopulation live in l
            for h=1:length(neighbors)
                j=neighbors(h);
                %S
                temp=S(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                S(j,:)=S(j,:)+dx;
                %E
                temp=E(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                E(j,:)=E(j,:)+dx;
                %dx_E_rec(l,:,t)=dx_E_rec(l,:,t)+dx;
                %Ir
                temp=Ir(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                Ir(j,:)=Ir(j,:)+dx;
                %dx_Ir_rec(l,:,t)=dx_Ir_rec(l,:,t)+dx;
                %Iu
                temp=Iu(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                Iu(j,:)=Iu(j,:)+dx;
                %dx_Iu_rec(l,:,t)=dx_Iu_rec(l,:,t)+dx;
                %dailyIr
                temp=dailyIr_prior(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                dailyIr_prior(j,:)=round(max(dailyIr_prior(j,:)+dx,0));
                %dx_dailyIr_prior_rec(l,:,t)=dx_dailyIr_prior_rec(l,:,t)+dx;
                %dailyIu
                temp=dailyIu_prior(j,:);
                A=cov(temp,obs_ens(l,:));
                rr=A(2,1)/prior_var;
                dx=rr*dy;
                dailyIu_prior(j,:)=round(max(dailyIu_prior(j,:)+dx,0));
                %dx_dailyIu_prior_rec(l,:,t)=dx_dailyIu_prior_rec(l,:,t)+dx;
            end
            %adjust alpha
            temp=para(alphamaps(l),:);
            A=cov(temp,obs_ens(l,:));
            rr=A(2,1)/prior_var;
            dx=rr*dy;
            para(alphamaps(l),:)=para(alphamaps(l),:)+dx;

            dx_alpha_rec(l,:,t)=dx'; %save Kalman gain for plotting

            %inflation alpha
            if std(para(alphamaps(l),:))<parastd(alphamaps(l))
                para(alphamaps(l),:)=mean(para(alphamaps(l),:),2)*ones(1,num_ens)+lambda*(para(alphamaps(l),:)-mean(para(alphamaps(l),:),2)*ones(1,num_ens));
            end

            %adjust beta
            temp=para(betamap(l),:);
            A=cov(temp,obs_ens(l,:));
            rr=A(2,1)/prior_var;
            dx=rr*dy;
            para(betamap(l),:)=para(betamap(l),:)+dx;

            dx_beta_rec(l,:,t)=dx'; %save Kalman gain for plotting

            %inflation beta
            if std(para(betamap(l),:))<parastd(betamap(l))
                para(betamap(l),:)=mean(para(betamap(l),:),2)*ones(1,num_ens)+lambda_beta*(para(betamap(l),:)-mean(para(betamap(l),:),2)*ones(1,num_ens));
            end

        end
    end


    if Stochastic == "y"
        para = checkbound_para(para,paramax,paramin,para_ori,alphamaps,betamap,flact_checkpara);
    else
        % IF DETERMINISTIC OUT OF BOUND PARA GETS THE INITIAL VALUE
        for i = 1:size(para, 1)
            % Create a mask for values outside the allowed range
            out_of_bounds = para(i, :) < paramin(i) | para(i, :) > paramax(i);
            % Replace ONLY the out-of-bound entries with the corresponding values from Day 1
            para(i, out_of_bounds) = para_ori(i, out_of_bounds);
        end
    end
    %%% reprobing of select parameters and state variables
    if doreprobe=="yes"
        if mod(t,reprobe_t)==0 % for every reprobe_t timesteps



            if Stochastic == "y"
                % randomly pick reprobe_percent ensemble members to resample
                num_reprobe=round(num_ens*reprobe_percent/100);
                reprobeind=randi([1 num_ens],num_reprobe,1);
            else
                t_reprobe=t_reprobe+1;
                reprobeind=fix_randi_reprobe(:,1);
            end

            % for r=reprobe_whichpara % loop through the parameters
            for nn=reprobeind' % loop through the sampled members
                para(reprobe_whichpara,nn)= para_ori(reprobe_whichpara,nn);
                if reprobeS=="yes"
                    S(:,nn)=  ceil(randi([5 95],num_mp,1) /100.*C);
                    E(:,nn)=  ceil(randi([0 20],num_mp,1) /100.*C);
                    Ir(:,nn)= ceil(randi([0 20],num_mp,1) /100.*C);
                    Iu(:,nn)= ceil(randi([0 20],num_mp,1) /100.*C);

                end
                [S,E,Ir,Iu]=checkbound_yesterday(S,E,Ir,Iu,C,S_yesterday,E_yesterday,Ir_yesterday,Iu_yesterday,t,Stochastic);
                    
                if Stochastic == "y"
                    para = checkbound_para(para,paramax,paramin,para_ori,alphamaps,betamap,flact_checkpara);
                else
                   % IF DETERMINISTIC OUT OF BOUND PARA GETS THE INITIAL VALUE
                    for i = 1:size(para, 1)
                        % Create a mask for values outside the allowed range
                        out_of_bounds = para(i, :) < paramin(i) | para(i, :) > paramax(i);
                        % Replace ONLY the out-of-bound entries with the corresponding values from Day 1
                        para(i, out_of_bounds) = para_ori(i, out_of_bounds);
                    end
                end
            end
        end
    end

    %update posterior Ir and Iu
    dailyIr_post=dailyIr_prior;
    dailyIu_post=dailyIu_prior;

    cumu_dailyIr_post=cumu_dailyIr_post+dailyIr_post;
    cumu_dailyIu_post=cumu_dailyIu_post+dailyIu_post;

    %%%%%%%%%%%%%%%%
    [S,E,Ir,Iu]=checkbound_yesterday(S,E,Ir,Iu,C,S_yesterday,E_yesterday,Ir_yesterday,Iu_yesterday,t,Stochastic);

    %%%%%%% save stavariables for yesterday checkbound
    S_yesterday=S;
    E_yesterday=E;
    Ir_yesterday=Ir;
    Iu_yesterday=Iu;


    %%%%%%% save posterior statevariables

    for i=1:num_loc
        for j=1:num_ens
            S_post(i,t,j)=sum(S(part(i):part(i+1)-1,j))./population(i);
            %S_rec(i,t,j)=sum(S(part(i):part(i+1)-1,j)); %real numbers, not percentage
            %E_post(i,t,j)=sum(E(part(i):part(i+1)-1,j))./population(i);
            %E_rec(i,t,j)=sum(E(part(i):part(i+1)-1,j));   %real numbers, not percentage
            %Ir_post(i,t,j)=sum(Ir(part(i):part(i+1)-1,j))./population(i);
            %Ir_rec(i,t,j)=sum(Ir(part(i):part(i+1)-1,j));   %real numbers, not percentage
            %Iu_post(i,t,j)= sum(Iu(part(i):part(i+1)-1,j))./population(i);
            %Iu_rec(i,t,j)= sum(Iu(part(i):part(i+1)-1,j));   %real numbers, not percentage
            dailyIr_post_rec(i,j,t)=sum(dailyIr_post(part(i):part(i+1)-1,j)); %real numbers, not percentage
            dailyIu_post_rec(i,j,t)=sum(dailyIu_post(part(i):part(i+1)-1,j));  %real numbers, not percentage
            cumu_dailyIr_post_rec(i,t,j)=sum(cumu_dailyIr_post(part(i):part(i+1)-1,j)); %real numbers, not percentage
            cumu_dailyIu_post_rec(i,t,j)=sum(cumu_dailyIu_post(part(i):part(i+1)-1,j)); %real numbers, not percentage
        end
    end

    para_post(:,:,t)=para;
    % Update and display the progress bar
    fprintf('%s [%s%s] %d/%d %.2f%%\r', nickname, repmat('|', 1, round(t/num_times*20)), repmat('-', 1, 20-round(t/num_times*20)),t, num_times, t/num_times*100);

    %% FORECAST

    if any(t == week_starts_days)
        fprintf('\n\n')
        tic

        forecast_num = forecast_num +1;
        fprintf('%s FORECASTING %d/%d at t = %d in: ...\n', nickname, forecast_num,length(week_starts_days),t);
        week = forecast_weeks(forecast_num);

        %fore_tstart = week_starts_days(week);

        fore_dailyIr = zeros(num_loc,num_times,num_ens);
        %fore_dailyIu = zeros(num_loc,num_times,num_ens);
        %fore_S  = zeros(num_loc,num_times,num_ens);
        %fore_E = zeros(num_loc,num_times,num_ens);
        %fore_Ir = zeros(num_loc,num_times,num_ens);
        %fore_Iu = zeros(num_loc,num_times,num_ens);


        fdailyIr = zeros(num_mp, num_ens);
        fdailyIu = zeros(num_mp, num_ens);
        fS = S;
        fE = E;
        fIr = Ir;
        fIu = Iu;

        % add true smothed dailyIr (obs_case) value to the days before the forecast
        % 1. Reshape truth to [num_loc, 1, t]
        % 2. Explicitly repmat (replicate) it to [num_loc, num_ens, t]
        % This forces the right-hand side to be [96, 200, 7], matching the left.
        fore_dailyIr(:,1:t,:) = repmat(reshape(obs_case(:, 1:t), [num_loc, t, 1]), [1, 1, num_ens]);

        for tt=(t+1):num_times % start the forcast from the day after t

            for k=1:num_ens
                if Stochastic == "y"
                    [fS(:,k), fE(:,k), fIr(:,k), fIu(:,k), fdailyIr(:,k), fdailyIu(:,k)] = integrate_model(nl, part, C, Cave, fS(:,k), fE(:,k), fIr(:,k), fIu(:,k), para(:,k), betamap, alphamaps);
                elseif Stochastic == "n"
                    [fS(:,k), fE(:,k), fIr(:,k), fIu(:,k), fdailyIr(:,k), fdailyIu(:,k)] = integrate_model_nopois(nl, part, C, Cave, fS(:,k), fE(:,k), fIr(:,k), fIu(:,k), para(:,k), betamap, alphamaps);
                else
                    error("Stochastic needs to be either 'y' or 'n' for deterministic")
                end
                if flights == "f"
                    % VECTORIZED PASSENGER FLOW CALCULATION

                    % Aggregate Ir and Iu by location using accumarray
                    Ir_sums = accumarray(location_indices, fIr(:,k), [num_locs, 1]);
                    Iu_sums = accumarray(location_indices, fIu(:,k), [num_locs, 1]);

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
                        fprintf('NEGATIVE RATES DETECTED at tt=%d, k=%d\n', tt, k);
                        fprintf('Number of negative i→j rates: %d\n', sum(neg_mask_ij));
                        fprintf('Number of negative j→i rates: %d\n', sum(neg_mask_ji));

                        % Set negative rates to zero
                        rates_i_to_j(neg_mask_ij) = 0;
                        rates_j_to_i(neg_mask_ji) = 0;
                    end

                    if Stochastic == "y"
                        % Generate all Poisson samples (vectorized)
                        rates_i_to_j = poissrnd(rates_i_to_j);
                        rates_j_to_i = poissrnd(rates_j_to_i);
                    end
                    % Compute net flows
                    net_deltas = rates_i_to_j - rates_j_to_i;

                    % Store for recording
                    %fore_delta_all_rec(t, k, :) = net_deltas;

                    % Apply updates using accumarray:
                    %B = accumarray(ind,data) sums groups of data by accumulating
                    % elements of a vector data according to the groups specified in ind.

                    % Changes to Iu for destination locations (gains)
                    delta_Iu_dest = accumarray(dest_locs, net_deltas, [num_locs, 1]);
                    % Changes to Iu for source locations (losses)
                    delta_Iu_src = accumarray(source_locs, -net_deltas, [num_locs, 1]);

                    % Apply to first index of each location
                    fIu(loc_first_idx, k) = max(fIu(loc_first_idx, k) + delta_Iu_dest, 0);
                    fIu(loc_first_idx, k) = max(fIu(loc_first_idx, k) + delta_Iu_src, 0);

                    % Same for S (opposite sign)
                    fS(loc_first_idx, k) = max(fS(loc_first_idx, k) - delta_Iu_dest, 0);
                    fS(loc_first_idx, k) = max(fS(loc_first_idx, k) - delta_Iu_src, 0);

                    % Update daily tracking
                    fdailyIu(loc_first_idx, k) = max(fdailyIu(loc_first_idx, k) + delta_Iu_dest, 0);
                    fdailyIu(loc_first_idx, k) = max(fdailyIu(loc_first_idx, k) + delta_Iu_src, 0);
                end
            end

            % Store the forecast results for the current time step
            for i = 1:num_loc
                idx_range = part(i):part(i+1)-1;
                fore_dailyIr(i,tt,:) = sum(fdailyIr(idx_range,:), 1);
                %fore_dailyIu(i,tt,:) = sum(fdailyIu(idx_range,:), 1);
                %fore_S(i,tt,:) = sum(S(idx_range,:), 1);
            end
        end
        % Finalize the forecast structure for the current week
        forecast_struct(forecast_num).nickname = nickname;
        forecast_struct(forecast_num).week_counter = week;
        forecast_struct(forecast_num).start_day = t;
        forecast_struct(forecast_num).truth_id = truth_id;
        forecast_struct(forecast_num).dailyIr = uint32(fore_dailyIr);
        %forecast_struct(forecast_num).dailyIu = uint32(fore_dailyIu);
        %forecast_struct(forecast_num).fore_S = uint32(fore_S);


        elapsed_sec=toc;
        fprintf('%.2f seconds\n\n', round(elapsed_sec));
    end

end
fprintf('\n')
%calculate means
dailyIr_prior_rec_mean = squeeze(mean(dailyIr_prior_rec,2));
dailyIu_prior_rec_mean = squeeze(mean(dailyIu_prior_rec,2));
dailyIr_post_rec_mean = squeeze(mean(dailyIr_post_rec,2));
dailyIu_post_rec_mean = squeeze(mean(dailyIu_post_rec,2));
cumu_dailyIr_post_rec_mean=squeeze(mean(cumu_dailyIr_post_rec,3));
cumu_dailyIu_post_rec_mean=squeeze(mean(cumu_dailyIu_post_rec,3));


cumu_dailyIr_post_mean=cumu_dailyIr_post_rec_mean./population;
cumu_dailyIu_post_mean=cumu_dailyIu_post_rec_mean./population;

% saving the big boys as int16, unit32 or single to save space
%delta_all_rec = int16(delta_all_rec);
cumu_dailyIu_post_rec=uint32(cumu_dailyIu_post_rec);
cumu_dailyIr_post_rec=uint32(cumu_dailyIr_post_rec);
dailyIr_post_rec = uint32(dailyIr_post_rec);
dailyIu_post_rec = uint32(dailyIu_post_rec);
dailyIr_prior_rec = uint32(dailyIr_post_rec);
dailyIu_prior_rec = uint32(dailyIu_post_rec);
dx_beta_rec = single(dx_beta_rec);
dx_alpha_rec = single(dx_alpha_rec);
dy_rec = single(dy_rec);
S_post = single(S_post);

%renaming and saving forecast file separately
%eval(['forecast_struct' num2str(run_id) ' = forecast_struct;']);
%clear forecast_struct
%save(file_name_fore, "forecast_struct*", "-v7.3")


%clear big vars we don't need to save:
clear Iu Iu_yesterday cumu_dailyIr_post Ir_yesterday dailyIu_prior cumu_dailyIu_post ...
    S Ir S_yesterday dailyIu_post E E_yesterday dailyIr_prior dailyIr_post para para_ori ...
    fS fE fIu fIr fdailyIr fdailyIu fore_dailyIr fore_dailyIu fore_S
%saving all remaning vars
save(all_file_name, '-v7.3')

%Plotting_testing_real(all_file_name)
