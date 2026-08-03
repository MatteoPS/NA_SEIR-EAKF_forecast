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
