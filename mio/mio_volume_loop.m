function p = mio_volume_loop(fun, I, M, opt, S)
% function p = mio_volume_loop(fun, I, M, opt, S)
%
% Applies the function fun to all voxels where M is positive
%
% In order to execute the loop in parallel, initiate parpool before
% executing this function. If number of workers > 1, volume loop will be
% executed in parallel
%
% fun - accepts one or two input arguments (signal vector + optionally
%          supplementary data)
%
% I   - 4D matrix
%
% M   - 3D mask
%
% opt - option structure
%
% S   - 4D supplementary data

if (nargin < 3), error('all inputs required'); end
if (nargin < 4), opt.present = 1; end
if (nargin < 5), S = []; else assert(~isempty(S), 'S cannot be empty if provided'); end

opt = mio_opt(opt);

% Manage supplementary data
if (~isempty(S))
    f = @(d) size(I,d) == size(S, d);
    assert( f(1) & f(2) & f(3), 'S and I must be of equal size');
    
    % use this structure to manage the loop both with and without
    % supplementary information
    f_fun = @(x,y) fun(x,y);
    f_sup = @(i,j,k) squeeze(S(i,j,k,:));
else
    f_fun = @(x,y) fun(x);
    f_sup = @(i,j,k) [];
end

% Init the output structure by fitting once to a voxel in the middle
%  (note that the output will be permuted before returning)
f = @(d) round(size(I,d)/2);
n_param = numel(f_fun(double(squeeze(I(f(1), f(2), f(3), :))),...
    f_sup(f(1), f(2), f(3))));
p = zeros(n_param, size(I,1), size(I,2), size(I,3));

try % start parpool outside this function to have it run in parfor mode
    tmp = gcp('nocreate');
    n_workers = tmp.NumWorkers;
catch
    n_workers = 1;
end

if (opt.mio.no_parfor), n_workers = 1; end


if opt.do_new_parfor
    
    siz = size(I);
    
    % Expand 4D volume to 1+1D so that n x m is samples times voxels
    I1 = reshape(I, prod(siz(1:3)), siz(4))';
    M1 = reshape(M, prod(siz(1:3)),      1)';
    I4 = zeros(n_param, prod(siz(1:3)));
    
    % Find all non masked voxels
    si = find((M1>0).*(~all(I1==0,1)));
    I2 = I1(:,si);
    
    % Define size of blocks for each worker
    d = ceil(size(I2,2) / n_workers);
    
    
    spmd
        i = labindex;
        s = (i-1)*d+1;
        e = i*d;
        
        if e > size(I2,2); e = size(I2,2); end
        
        out = zeros(n_param, e-s+1);
        in  = I2(:, s:e);
        
        for k = 1:size(out,2)
            out(:, k) = f_fun(double(squeeze(in(:,k))));
        end
    end
    
    % Combine result from workers
    I3 = [];
    for i = 1:n_workers
        I3 = cat(2, I3, out{i});
    end
    
    % Revert mask subsampling
    I4(:,si) = I3;
    
    % Revert 1+1D to 4D transform so that we get "x, y, z, parameter" dimensions
    p = reshape(I4', siz(1), siz(2), siz(3), n_param);
    
else
    
    % Loop over the data
    if (opt.verbose), fprintf('Starting the loop. Workers = %i\n', n_workers); end
    for k = 1:size(I,3)
        if (opt.verbose), fprintf('k=%3.0i', k); end
        for j = 1:size(I,2)
            
            if (any(M(:,j,k)))
                if (n_workers == 1) % single core
                    for i = 1:size(I,1)
                        if (M(i,j,k) == 0), continue; end
                        if (all(I(i,j,k,:) == 0)), continue; end
                        p(:,i,j,k) = f_fun(double(squeeze(I(i,j,k,:))), f_sup(i,j,k));
                    end
                    
                else % multicore
                    % tried to put the parfor in another loop structure,
                    % but it did not improve performance much
                    parfor i = 1:size(I,1)
                        if (M(i,j,k) == 0), continue; end
                        if (all(I(i,j,k,:) == 0)), continue; end
                        q = feval(f_sup,i,j,k);
                        p(:,i,j,k) = f_fun(double(squeeze(I(i,j,k,:))), q);
                    end
                end
            end
            
            % print a status report
            if (any(M(:,j,k))), marker = 'o'; else marker = '.'; end
            if ((mod(j,4) == 0) && opt.verbose), fprintf(marker); end
        end
        if (opt.verbose), disp(';'); end
    end
    
    p = permute(p, [2 3 4 1]);
end

