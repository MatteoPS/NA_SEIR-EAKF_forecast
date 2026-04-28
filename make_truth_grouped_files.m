%% creates a single struct with all the synthetic outbreak truth variables
% used in make_forcast_metrics.m
truthfileList = dir('Truths/truth_t*');
truthfileList = truthfileList(~startsWith({truthfileList.name}, '.')); %avoids hidden files
struct_truth= struct('truth_id', {}, 'truth_nick', {}, 'truth_vars', {});


for h = 1:length(truthfileList)
    temp = load(['Truths/' truthfileList(h).name]);
    struct_truth(h).truth_id = temp.truth_id;
    struct_truth(h).truth_nick = temp.truth_nick;
    struct_truth(h).truth_vars = temp;  % all truth srtucture in a field of the main struct    
    clearvars temp
end

save("Truths/1118_all_truths_struct.mat","struct_truth")

%how to retrieve:
%truth_dailyIu_post_rec1 = struct_truth(1).truth_vars.truth_dailyIu_post_rec

%% group model runs main vars
%{
fileList = dir('Model_Runs/');
fileList = fileList(~startsWith({fileList.name}, '.')); %avoids hidden files
struct_runs= struct('para_post', {},'dailyIr_post_rec', {},'dailyIu_post_rec', {}, 'run_id', {}, 'truth_id', {}, 'nickname', {}, 'truth_nick', {});

for i = 1:length(fileList)
    fileList_name = fileList(i).name;
    
    % Load into a temporary struct to avoid overwriting variables
    temp = load(['Model_Runs/' fileList_name]);
    
    struct_runs(i).para_post = temp.para_post;
    struct_runs(i).dailyIr_post_rec = dailyIr_post_rec;
    struct_runs(i).dailyIu_post_rec = dailyIu_post_rec;
    struct_runs(i).run_id = temp.run_id;
    struct_runs(i).truth_id = temp.truth_id;
    struct_runs(i).nickname = temp.nickname;
    struct_runs(i).truth_nick = temp.truth_nick;
    
    clearvars temp
end
%}