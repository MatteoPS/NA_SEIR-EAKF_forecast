%% PLOT_ALPHA_BETA_RUN
% Diagnostic script: groups the posterior alpha/beta/S/dailyIr estimates of
% every model run by scenario attribute (strain, flights, commuting) and
% exports one figure per combination.
%
% Exploratory script -- run it section by section. Requires completed model
% runs in results/model_runs/ (see RUN_PIPELINE).

paths = setup_paths();

load(paths.truth_stats);   % -> truth_stats
load(paths.population);    % -> population

runs_description = read_runs_table(paths);

% Initialize PDF export
pdf_filename   = fullfile(paths.figures, 'grouped_alpha_beta-S-dailyIr.pdf');
checkpoint_file = fullfile(paths.model_runs, 'plot_alpha_beta_run_checkpoint.mat');

% get default colors array
gcapal = get(gca, 'ColorOrder');
close


%% runs loop
para_struct=struct(); %create para_struct to group runs

for run=1:size(runs_description,1)
    para_struct(run).nickname =  string(runs_description.nickname(run));
    para_struct(run).run_id = string(runs_description.RunIDtext(run));
    para_struct(run).truth_id = string(runs_description.TruthID(run));
    para_struct(run).strain = string(runs_description.Strain(run));
    para_struct(run).seed_loc = string(runs_description.Seed_loc(run));
    para_struct(run).flights = string(runs_description.Flights(run));
    para_struct(run).Commuting = string(runs_description.Commuting(run));
    files = dir(fullfile(paths.model_runs, ['*_' char(para_struct(run).run_id) '_*.mat']));

    if isscalar(files)
        load(fullfile(files(1).folder, files(1).name), 'para_post', 'alphamaps', 'betamap', 'truth_para_post', ...
            'dailyIr_post_rec', 'dailyIr_post_rec_mean', 'truth_noisy_dailyIr_rec','truth_dailyIr_post_rec', ...
            'S_post', '','truth_S_post', ...
            'all_file_name');
    elseif length(files) == 2
        error('Error loading Model run file. Two files found: %s and %s', files(1).name, files(2).name);
    else
        error('Error loading Model run file. Expected 1 file, found %d matching *%s*.mat', length(files), nickname);
    end

    para_struct(run).para_post=para_post;
    para_struct(run).alphamaps=alphamaps;
    para_struct(run).betamap=betamap;
    para_struct(run).truth_para_post = truth_para_post;
    para_struct(run).dailyIr_post_rec = dailyIr_post_rec;
    para_struct(run).dailyIr_post_rec_mean = dailyIr_post_rec_mean;
    para_struct(run).truth_noisy_dailyIr_rec = truth_noisy_dailyIr_rec;
    para_struct(run).truth_dailyIr_post_rec = truth_dailyIr_post_rec;
    para_struct(run).S_post = S_post;
    para_struct(run).truth_S_post = truth_S_post;

    para_struct(run).all_file_name = all_file_name;
end


%group runs estimates by attibute (flight,commuting and strain)
strains = string({para_struct.strain});
flights = string({para_struct.flights});
Commuting = string({para_struct.Commuting});
combinations = unique([strains' flights' Commuting'], 'rows');
attributes = table(combinations(:,1), combinations(:,2), combinations(:,3), ...
    'VariableNames', {'strain','flights','Commuting'});

% Create mapping dictionaries
strain_map = containers.Map({'ls', 'lo', 'me', 'hi', 'hs'}, ...
    {'lowest', 'low', 'medium', 'high', 'highest'});
flights_map = containers.Map({'f', 'nf'}, ...
    {'flight', 'no flight'});
commuting_map = containers.Map({'p', 'n'}, ...
    {'patch', 'network'});

% Create labels by concatenating mapped values
labels = [];
for i = 1:height(attributes)
    strain_label = strain_map(char(attributes.strain(i)));
    flights_label = flights_map(char(attributes.flights(i)));
    commuting_label = commuting_map(char(attributes.Commuting(i)));
    label = strain_label + ", " + flights_label + ", " + commuting_label;
    labels = [labels; string(label)];
end

attributes.label = labels;
% Reorder: strain (ls→hs), flight (nf→f), Commuting (p→n)
attributes.strain = categorical(attributes.strain, {'ls', 'lo', 'me', 'hi', 'hs'}, 'Ordinal', true);
attributes.Commuting = categorical(attributes.Commuting, {'p', 'n'}, 'Ordinal', true);
attributes.flights = categorical(attributes.flights, {'nf', 'f'}, 'Ordinal', true);

attributes = sortrows(attributes, {'strain',  'Commuting','flights'});

clearvars -except para_struct pdf_filename checkpoint_file paths population runs_description ...
    truth_stats alphamaps betamap attributes gcapal
save(checkpoint_file, '-v7.3')

%% load checkpoint and run from here to save time
paths = setup_paths();
load(fullfile(paths.model_runs, 'plot_alpha_beta_run_checkpoint.mat'))

for aa=1:height(attributes)

    strain = string(attributes.strain(aa));
    flights = string(attributes.flights(aa));
    Commuting = string(attributes.Commuting(aa));
    label = string(attributes.label(aa));

    idx = [para_struct.strain] == strain & ...
        [para_struct.flights] == flights & ...
        [para_struct.Commuting] == Commuting;
    current_struct = para_struct(idx);


    % Convert the truth_stats IDs to a string array using curly braces {}
    % Run ismember (now comparing string array vs string array)
    mask = ismember(string({truth_stats.id}), [current_struct.truth_id]);
    true_peak_weeks = [truth_stats(mask).peak_week];
    true_peak_weeks = true_peak_weeks(:);
    true_peak_weeks_day = true_peak_weeks .*7;
    % Concatenates along dim 2 (ensembles). New size: [196, (150*7), 365]
    cat_para_post = cat(2, current_struct.para_post);
    cat_alpha=cat_para_post(alphamaps,:,:);
    cat_beta=cat_para_post(betamap,:,:);

    cat_dailyIr_post = cat(2, current_struct.dailyIr_post_rec);
    cat_dailyIr_post = double(cat_dailyIr_post) ./ population;

    cat_S_post = cat(3, current_struct.S_post);


    alpha_ens=squeeze(mean(cat_alpha, 1));
    beta_ens=squeeze(mean(cat_beta, 1));
    dailyIr_ens= squeeze(mean(cat_dailyIr_post, 1));
    S_ens = squeeze(mean(cat_S_post , 1));            


    mean_alpha=mean(alpha_ens,1);
    mean_beta=mean(beta_ens,1);
    mean_dailyIr=mean(dailyIr_ens,1);
    mean_S=mean(S_ens,2);

    lb_alpha = prctile(alpha_ens, 2.5,1);
    ub_alpha = prctile(alpha_ens, 97.5,1);
    lb_beta = prctile(beta_ens, 2.5,1);
    ub_beta = prctile(beta_ens, 97.5,1);
    lb_dailyIr = prctile(dailyIr_ens, 2.5,1);
    ub_dailyIr = prctile(dailyIr_ens, 97.5,1);
    lb_S = prctile(S_ens, 2.5,2);
    ub_S = prctile(S_ens, 97.5,2);



    fig = figure('visible', 'off');
    tl=tiledlayout(2,2); % Create a tiled layout for the figures
    nexttile;
    hold on
    al=plot(mean_alpha,'LineWidth',2,'Color',gcapal(1,:));
    plot(lb_alpha,"--",'Color',gcapal(1,:));
    plot(ub_alpha,"--",'Color',gcapal(1,:));
    yline(current_struct(1).truth_para_post(alphamaps(1))) %WORKS FOR FIXED ALPHA ONLY
    xline(true_peak_weeks_day,"k",'Alpha',0.02)
    ylim([0 0.6])
    legend(al,"\alpha")
    hold off
    nexttile;

    hold on
    be=plot(mean_beta,'LineWidth',2,'Color',gcapal(2,:));
    plot(lb_beta,"--",'Color',gcapal(2,:));
    plot(ub_beta,"--",'Color',gcapal(2,:));
    yline(current_struct(1).truth_para_post(betamap(1))) %WORKS FOR FIXED beta ONLY
    xline(true_peak_weeks_day,"k",'Alpha',0.02)
    ylim([0 5])
    legend(be,"\beta");
    hold off
    nexttile;
    
    hold on
    su=plot(mean_dailyIr,'LineWidth',2,'Color',gcapal(5,:));
    plot(lb_dailyIr,"--",'LineWidth',1.5,'Color',gcapal(5,:));
    plot(ub_dailyIr,"--",'LineWidth',1.5,'Color',gcapal(5,:));
    %yline(current_struct(1).truth_para_post(betamap(1)))
    xline(true_peak_weeks_day,"k",'Alpha',0.02)
    %ylim([0 1])
    legend(su,"dailyIr");
    hold off
    nexttile;

    hold on
    su=plot(mean_S,'LineWidth',2,'Color',gcapal(4,:));
    plot(lb_S,"--",'Color',gcapal(4,:));
    plot(ub_S,"--",'Color',gcapal(4,:));
    %yline(current_struct(1).truth_para_post(betamap(1)))
    xline(true_peak_weeks_day,"k",'Alpha',0.02)
    ylim([0 1])
    legend(su,"S");
    hold off



    title(tl, label)


    this_filename = sprintf('%s%03d.png',pdf_filename,  aa);
    
    % 3. Export single file
    exportgraphics(fig, this_filename, 'ContentType', 'image', 'Resolution', 300);
    
    % 4. Clean up immediately to free memory
    close(fig);

    % 
    % % Export to PDF
    % if aa == 1
    %     % First page - create new PDF
    %     exportgraphics(fig, pdf_filename, 'ContentType', 'image', 'Resolution', 300);
    % else
    %     % Append to existing PDF
    %     exportgraphics(fig, pdf_filename, 'ContentType', 'image', 'Resolution', 300, 'Append', true);
    % end
    % 
    % close(fig);
end

% % 1. Define the pattern of files you just created (e.g., 'MyGraph001.png')
% input_pattern = sprintf('%s*.png', pdf_filename); % or *.pdf
% output_file = pdf_filename;
% 
% % 2. Construct the bash command
% % Ensure script is executable first: chmod +x Output/PDF_page_wrapper.sh
% cmd = sprintf('./Output/PDF_simple_page_wrapper.sh %s %s', input_pattern, output_file);
% 
% % 3. Run it
% [status, cmdout] = system(cmd);
% 
% if status ~= 0 
%     disp(['Error: ' cmdout]); 
% end
% 



