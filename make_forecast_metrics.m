

%% This script creates a forecast structure for each model run file in Model_Runs
% run this before aggregating the results with
% 'make_forecast_metrics_groups*.m'

load Truths/1118_all_truths_stats.mat
load population.mat
% Get nicknames from runs-description
opts = detectImportOptions("Runs-description.xlsx");
opts.DataRange = 'A2'; % Start reading from A2
runs_description = readtable("Runs-description.xlsx", opts);
clear opts

file_pattern = "Model_Runs/*_synth_*.mat"
file_list = dir(file_pattern);

% Define onset thresholds to calculate metrics for
onset_thresholds = [100, 150];% Add or remove thresholds as needed
%define the name of the peak variables
peak_targets = ["peak_week", "peak_inci"];

%% runs loop
% run forecast metrics for each run. no aggregation
%for run=1:size(runs_description,1)
for f_idx = 1:length(file_list)
    current_file_path = fullfile(file_list(f_idx).folder, file_list(f_idx).name);
    current_file_name = file_list(f_idx).name;
    
    fprintf('Processing: %s\n', current_file_name);
    load(current_file_path, 'forecast_struct', 'all_file_name' ,'nickname','run_id','truth_id','strain','seed_loc','flights','Commuting'  ); 
    
    truth_current = truth_stats(strcmp({truth_stats.id}, truth_id));
    %% forcast start week loop
    for t=1:length(forecast_struct)
        
        %collect absolute week number (i start forcasting from week 2 -day 7
        forecast_struct(t).forecast_week_abs = forecast_struct(t).week_counter + 1;
        % Sum cases for each week + convert to rate over 100K
        num_times = size(forecast_struct(t).dailyIr, 2); % Get the number of time points
        num_weeks = floor(num_times / 7);
        for week = 1:num_weeks
            start_day = (week - 1) * 7 + 1;
            end_day = week * 7;
            forecast_struct(t).dailyIr_100K_week(:,week,:) =single(sum(forecast_struct(t).dailyIr(:, start_day:end_day,:), 2)./ population * 100000);
            %forecast_struct(t).dailyIu_100K_week(:,week,:) =single(sum(forecast_struct(t).dailyIu(:, start_day:end_day,:), 2)./ population * 100000);
        end

        % Calculate onset weeks for all thresholds
        for wn_idx = 1:length(onset_thresholds)
            wn = onset_thresholds(wn_idx);
            field_name = sprintf('onset%d', wn);

            [~, onset_week] = max(forecast_struct(t).dailyIr_100K_week >= wn, [], 2); % max along dimension 2 (weeks)
            onset_week(~any(forecast_struct(t).dailyIr_100K_week >= wn, 2)) = NaN; % ensable that don't reach the onset rate
            forecast_struct(t).(field_name) = single(squeeze(onset_week));
        end

        %peak week - peak amount
        [peak_inci, peak_week] = max( forecast_struct(t).dailyIr_100K_week, [], 2);
        forecast_struct(t).peak_week=int8(squeeze(peak_week));
        forecast_struct(t).peak_inci=single(squeeze(peak_inci));

        % Calculate metrics for all onset thresholds
        num_locations = size(forecast_struct(t).dailyIr_100K_week, 1);
        %% onset tresholds loop
        for wn_idx = 1:length(onset_thresholds)
            wn = onset_thresholds(wn_idx);
            field_name = sprintf('onset%d', wn);
            truth_field = sprintf('onset%d', wn);

            % set onset:
            truth_onset = truth_current.(truth_field);
            forecast_ensemble = forecast_struct(t).(field_name);

            % Get a template of the metrics structure
            metrics_template = calculate_forecast_metrics([], NaN);
            
            % Pre-allocate a structure array to hold all location metrics
            metrics_array = repmat(metrics_template, num_locations, 1);
            
            % --- Fill the pre-allocated array ---
            for loc = 1:num_locations
                truth_value = truth_onset(loc);
                forecast_values = forecast_ensemble(loc, :);
                
                % Function handles NaN truth_value internally
                metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
            end
            
            % Assign the entire completed array to the struct field at once
            forecast_struct(t).([field_name '_metrics']) = metrics_array;

        end

        %% peak week and peak inci loop
       
        for p_idx = 1:length(peak_targets)
            field_name = peak_targets(p_idx);
            truth_field = field_name; % Assumes truth_current has fields 'peak_week' and 'peak_inci'
            
            % Get the vector of truth values (one per location)
            truth_values = truth_current.(truth_field);
            
            % Get the ensemble forecast [loc x ensemble_members]
            forecast_ensemble = forecast_struct(t).(field_name);
            
            % --- Pre-allocate metrics array for efficiency ---
            metrics_template = calculate_forecast_metrics([], NaN);
            metrics_array = repmat(metrics_template, num_locations, 1);
            
            % --- Fill the pre-allocated array ---
            for loc = 1:num_locations
                truth_value = truth_values(loc);
                forecast_values = forecast_ensemble(loc, :);
                
                % Function handles NaN truth_value internally
                metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
            end
            
            % Assign the entire completed array to the struct field
            metrics_field_name = sprintf('%s_metrics', field_name);
            forecast_struct(t).(metrics_field_name) = metrics_array;
        end
    end
    forecast_file_name=replace(all_file_name, ["Model_Runs/", ".mat"], ["Forecasts/", "_fore_res_group"]);
    fprintf('saving %s \n\n', forecast_file_name);
    save(forecast_file_name, "forecast_struct","forecast_file_name","nickname")
end


function metrics = calculate_forecast_metrics(forecast_ensemble, truth_value, alpha_levels)
% Calculate forecast evaluation metrics for ensemble forecasts
% Adapted for evaluating a single model across multiple synthetic outbreaks
%
% Inputs:
%   forecast_ensemble: [1 x N] or [N x 1] array of ensemble forecasts
%   truth_value: scalar observed value
%   alpha_levels: (optional) vector of prediction interval levels for WIS
%                 Default: [0.02, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90]
%
% Outputs:
%   metrics: structure containing:
%       .wis: Weighted Interval Score
%       .ae: Absolute Error (median forecast)
%       .mae: Mean Absolute Error (mean of individual ensemble member errors)
%       .median: forecast median
%       .mean: forecast mean
%       .coverage: structure with coverage (0 or 1) for each interval level
%       .quantiles: structure with all computed quantiles
%       .ensemble_spread: standard deviation of ensemble
%       .bias: forecast median - truth (positive = overestimate)
%       .wis_sharpness: Component of WIS due to interval width
%       .wis_penalty: Component of WIS due to missing the truth
%       .sharpness_fraction: Ratio of Sharpness to Total WIS (0 to 1)
%
% Returns NaN for metrics if calculation is not possible

if nargin < 3 || isempty(alpha_levels)
    alpha_levels = [0.02, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90];
end
% Ensure forecast_ensemble is a row vector and remove NaNs
forecast_ensemble = forecast_ensemble(:)'; 
forecast_clean = double(forecast_ensemble(~isnan(forecast_ensemble)));

% Initialize output structure with NaN values
metrics = struct();
metrics.wis = NaN;
metrics.ae = NaN;
metrics.mae = NaN;
metrics.median = NaN;
metrics.mean = NaN;
metrics.bias = NaN;
metrics.ensemble_spread = NaN;
metrics.wis_sharpness = NaN; 
metrics.wis_penalty = NaN;
metrics.sharpness_fraction = NaN;

metrics.coverage = struct();
metrics.quantiles = struct();

% Initialize all coverage fields with NaN
for k = 1:length(alpha_levels)
    field_name = sprintf('interval_%d', round((1 - alpha_levels(k))*100));
    metrics.coverage.(field_name) = NaN;
end

% Return NaN structure if truth is NaN or no valid forecasts
if any(isnan(truth_value)) || isempty(forecast_clean) || isempty(truth_value)
    return;
end
if numel(truth_value) > 1
    error('truth_value must be a scalar value');
end

%% Calculate Basic Statistics
m = median(forecast_clean);
metrics.median = m;
metrics.mean = mean(forecast_clean);
metrics.ensemble_spread = std(forecast_clean);
metrics.ae = abs(truth_value - m);
metrics.mae = mean(abs(forecast_clean - truth_value));
metrics.bias = m - truth_value;

%% Calculate WIS Decomposition
K = length(alpha_levels); 
w0 = 0.5;

% 1. Initialize components
% The median contribution (w0 * AE) is purely a penalty because width is 0.
sum_penalty = w0 * abs(truth_value - m);
sum_sharpness = 0; 

for k = 1:K
    alpha_k = alpha_levels(k);
    
    l = quantile(forecast_clean, alpha_k / 2); 
    u = quantile(forecast_clean, 1 - alpha_k / 2); 
    
    field_name = sprintf('interval_%d', round((1 - alpha_k)*100));
    metrics.quantiles.(field_name).lower = l;
    metrics.quantiles.(field_name).upper = u;
    metrics.quantiles.(field_name).width = u - l;
    
    % 2. Calculate Components Separately
    current_sharpness = u - l;
    
    current_penalty = 0;
    if truth_value < l
        current_penalty = (2 / alpha_k) * (l - truth_value);
    elseif truth_value > u
        current_penalty = (2 / alpha_k) * (truth_value - u);
    end
    
    wk = alpha_k / 2;
    
    % 3. Accumulate Weighted Sums
    sum_sharpness = sum_sharpness + (wk * current_sharpness);
    sum_penalty = sum_penalty + (wk * current_penalty);
    
    % Coverage logic
    is_covered = (truth_value >= l) & (truth_value <= u);
    metrics.coverage.(field_name) = double(is_covered);
end

% 4. Normalize and Store
normalization_factor = K + 0.5;

metrics.wis = (sum_sharpness + sum_penalty) / normalization_factor;
metrics.wis_sharpness = sum_sharpness / normalization_factor;
metrics.wis_penalty = sum_penalty / normalization_factor;

% 5. Fraction Calculation (0 to 1)
% Use eps to avoid division by zero if WIS is perfect (0)
metrics.sharpness_fraction = metrics.wis_sharpness / (metrics.wis + eps);

end
