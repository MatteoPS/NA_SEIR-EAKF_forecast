%% make_forecast_group_real_country.m
% Aggregates real data forecast metrics, grouped by Country code from statecodes.
% Output structure: all_real_data.(Settings_Country).(SliceName).(Target).(BinName)

% 1. Setup
load statecodes.mat
load population.mat
load Truths/1211_real_stats.mat 

% [601:604] real pois
real_pois = 601:604;
% [701:704] real det
real_det = 701:704;
run_ids=[real_pois,real_det]


% Map location indices to Country Codes (Var3)
loc_countries = statecodes.Var3; 

output_dir = 'Forecasts_real_agg';
if ~exist(output_dir, 'dir'), mkdir(output_dir); end
summary_filename = fullfile(output_dir, 'real_data_aggregated_country.mat');

% Define targets and metrics
all_targets = [ "onset25", "onset50", "onset100", "onset200", "onset300", "peak_week", "peak_inci"];
metrics_to_collect = ["wis", "ae", "mae", "ensemble_spread", "wis_sharpness", "wis_penalty", "sharpness_fraction"];
coverage_to_collect = ["interval_90", "interval_50"];

% 2. Find Real Forecast Files
file_list = []; % Initialize empty struct

for i = 1:length(run_ids)
    % Construct pattern: Forecasts/*_341_*_fore_real_stats.mat
    current_pattern = sprintf('Forecasts/*_%d_*_fore_real_stats.mat', run_ids(i));

    % Fetch and append
    files_found = dir(current_pattern);
    file_list = [file_list; files_found]; 
end

% Structure to hold final output
all_real_data = struct(); 

%% 3. Main Loop over Files (Models)
for f_idx = 1:length(file_list)
    current_file_path = fullfile(file_list(f_idx).folder, file_list(f_idx).name);
    fprintf('Processing file: %s\n', file_list(f_idx).name);
    
    % --- LOAD COMMAND ------------------------------------------
    forecast_struct = load(current_file_path, 'forecast_struct').forecast_struct;
    % -----------------------------------------------------------
    
    settings = string(extractBetween(file_list(f_idx).name, 'real_', '_fore'));
    
    % Initialize a container separated by COUNTRY first
    % Structure: slice_bins.(Country).(Slice).(Target).(Bin).(Metric)
    slice_bins = struct();
    
    %% 4. Loop over Forecast Weeks (t)
    T_weeks = length(forecast_struct);
    
    for t = 1:T_weeks
        if isempty(forecast_struct(t).slices)
            continue;
        end
        
        available_slices = fieldnames(forecast_struct(t).slices);
        
        %% 5. Loop over Slices
        for s_idx = 1:length(available_slices)
            slice_name = available_slices{s_idx};
            slice_data = forecast_struct(t).slices.(slice_name);
            
            % --- A. Loop Targets ---
            for target_idx = 1:length(all_targets)
                target_name = all_targets(target_idx);
                metrics_field = sprintf('%s_metrics', target_name);
                
                if ~isfield(slice_data, metrics_field)
                    continue;
                end
                
                metrics_struct = slice_data.(metrics_field);
                
                % --- B. Loop Locations ---
                num_locs = length(metrics_struct);
                
                for loc = 1:num_locs
                    
                    % Identify Country
                    current_country = loc_countries{loc};
                    
                    % 1. Get Absolute Truth
                    true_week_abs = get_true_event_week(real_stats, slice_name, target_name, loc);
                    
                    if isnan(true_week_abs) || true_week_abs == 0
                        continue; 
                    end
                    
                    % 2. Calculate Alignment
                    weeks_to_event = t - true_week_abs;
                    
                    if weeks_to_event >= 0
                        bin_name = sprintf('week_p%d', weeks_to_event);
                    else
                        bin_name = sprintf('week_m%d', abs(weeks_to_event));
                    end
                    
                    % Initialize country struct if missing
                    if ~isfield(slice_bins, current_country)
                        slice_bins.(current_country) = struct();
                    end
                    
                    % 3. Collect Standard Metrics
                    for m_idx = 1:length(metrics_to_collect)
                        m_name = metrics_to_collect(m_idx);
                        if isfield(metrics_struct(loc), m_name)
                            val = metrics_struct(loc).(m_name);
                            if ~isnan(val)
                                slice_bins.(current_country) = bin_value(slice_bins.(current_country), slice_name, target_name, bin_name, m_name, val);
                            end
                        end
                    end
                    
                    % 4. Collect Coverage Metrics
                    for c_idx = 1:length(coverage_to_collect)
                        m_name = coverage_to_collect(c_idx);
                        if isfield(metrics_struct(loc), 'coverage') && isfield(metrics_struct(loc).coverage, m_name)
                            val = metrics_struct(loc).coverage.(m_name);
                            slice_bins.(current_country) = bin_value(slice_bins.(current_country), slice_name, target_name, bin_name, m_name, val);
                        end
                    end
                    
                end % loc loop
            end % target loop
        end % slice loop
    end % t loop
    
    %% 6. Aggregate Bins per Country and Slice
    found_countries = fieldnames(slice_bins);
    
    for c = 1:length(found_countries)
        cc = found_countries{c}; % Country Code (e.g., 'US', 'CA')
        country_data = slice_bins.(cc);
        
        found_slices = fieldnames(country_data);
        
        for s = 1:length(found_slices)
            s_name = found_slices{s};
            
            % Aggregate raw bins into Mean/Median stats
            summary_stats = aggregate_bins(country_data.(s_name), all_targets, [metrics_to_collect, coverage_to_collect]);
            
            % Create distinct model structure: settings_CountryCode
            group_name = sprintf('%s_%s', settings, cc);
            
            if ~isfield(all_real_data, group_name)
                all_real_data.(group_name) = struct();
            end
            
            all_real_data.(group_name).(s_name) = summary_stats;
        end
    end
    
end

% Save
fprintf('Saving aggregated real data to %s\n', summary_filename);
save(summary_filename, '-struct', 'all_real_data', '-v7.3');
fprintf('Done.\n');


%% --- HELPER FUNCTIONS ---

function true_week_abs = get_true_event_week(real_stats, slice_name, target_name, loc)
    true_week_abs = NaN;
    if ~isfield(real_stats, slice_name), return; end
    
    truth_slice = real_stats.(slice_name);
    truth_field = '';

    if startsWith(target_name, "peak")
        if isfield(truth_slice, 'peak_week_abs')
            truth_field = 'peak_week_abs';
        elseif isfield(truth_slice, 'peak_week')
            truth_field = 'peak_week';
        end
    elseif startsWith(target_name, "onset")
        truth_field = target_name;
    end

    if ~isempty(truth_field) && isfield(truth_slice, truth_field)
        val = truth_slice.(truth_field);
        if loc <= length(val)
            true_week_abs = double(val(loc));
        end
    end
end

function bins = bin_value(bins, slice_name, target_name, bin_name, m_name, val)
    % Ensures the nested structure exists: bins.(slice).(target).(week).(metric)
    if ~isfield(bins, slice_name), bins.(slice_name) = struct(); end
    if ~isfield(bins.(slice_name), target_name), bins.(slice_name).(target_name) = struct(); end
    if ~isfield(bins.(slice_name).(target_name), bin_name), bins.(slice_name).(target_name).(bin_name) = struct(); end
    if ~isfield(bins.(slice_name).(target_name).(bin_name), m_name), bins.(slice_name).(target_name).(bin_name).(m_name) = []; end
    
    bins.(slice_name).(target_name).(bin_name).(m_name)(end+1) = val;
end

function summary = aggregate_bins(bins, all_targets, all_metrics)
    summary = struct();
    if isempty(fieldnames(bins)), return; end
            
    for target_name_cell = all_targets
        target = target_name_cell{:}; 
        if ~isfield(bins, target), continue; end
        
        weeks = fieldnames(bins.(target));
        for w_i = 1:length(weeks)
            bin_name = weeks{w_i};
            
            for m_name_cell = all_metrics
                m_name = m_name_cell{:};
                if ~isfield(bins.(target).(bin_name), m_name), continue; end
                
                vals = bins.(target).(bin_name).(m_name);
                if isempty(vals), continue; end
                
                summary.(target).(bin_name).(strcat('mean_', m_name)) = mean(vals, 'omitnan');
                summary.(target).(bin_name).(strcat('median_', m_name)) = median(vals, 'omitnan');
                summary.(target).(bin_name).num_samples = length(vals);
            end
        end
    end
end