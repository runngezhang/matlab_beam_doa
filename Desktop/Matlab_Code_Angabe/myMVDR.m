function [sig, W] = myMVDR(cfg, sig)
%MYMVDR performs beamforming using the classical MVDR beamformer
% Input parameters:
%   * sig:  struct containing the source and microphone signal(s)
%   * cfg:  struct containing configuration parameters
% 
% Output parameters:
%   * sig:  struct that will also contain the output signal
%   * W:    matrix containing beamforming coefficients for each subband

cfg.mic_pos.x = [-7.5e-2 -3.375e-2 0 3.375e-2 7.5e-2];
cfg.mic_pos.y = [-6e-2 -0.75e-2 0 -0.75e-2 -6e-2];
cfg.mic_pos.z = [-4e-2 0 0 0 -4e-2]; 
cfg.c = 342; %speed of sound in air

%% filterbank initialization
cfg.K = 512; % FFT size
cfg.N = 128; % frame shift
cfg.Lp = 1024; % prototype filter length
%p=IterLSDesign(cfg.Lp,cfg.K,cfg.N);
%cfg.p=IterLSDesign(cfg.Lp,cfg.K,cfg.N);
%cfg.frange = 0:250:8000;
cfg.frange = linspace(0,cfg.fs/2,cfg.K/2+1)'; % frequency axis
cfg.k_range = 2*pi*cfg.frange/cfg.c;
%--------------------------------------------------------------------------
%create input data blocks and create subbands
%--------------------------------------------------------------------------
for idx_mic = 1:cfg.nmic    
    %get the frequency subbands for each block -> X of dimension (#subbands, #blocks, #microphones)
    %of microphone data
    %X(:,:,idx_mic) = DFTAnaRealEntireSignal(sig.x(:,idx_mic),cfg.K,cfg.N,cfg.p);
    [X(:,:,idx_mic), F, T] = stft(sig.x(:,idx_mic),512,128,512,cfg.fs);
    %of desired signal components
    %X_des(:,:,idx_mic) = DFTAnaRealEntireSignal(sig.xSrc(:,idx_mic,1),cfg.K,cfg.N,cfg.p);
    X_des(:,:,idx_mic) = stft(sig.xSrc(:,idx_mic,1),512,128,512,cfg.fs);
    %of interference+noise
    if cfg.noise_type
        X_int(:,:,idx_mic) = DFTAnaRealEntireSignal(sum(sig.xSrc(:,idx_mic,2:end),3)...
            +sig.xnoise(:,idx_mic), cfg.K,cfg.N,cfg.p);
    else
        %X_int(:,:,idx_mic) = DFTAnaRealEntireSignal(sum(sig.xSrc(:,idx_mic,2:end),3),cfg.K,cfg.N,cfg.p);
        X_int(:,:,idx_mic) = stft(sum(sig.xSrc(:,idx_mic,2:end),3),512,128,512,cfg.fs);
    end
end

%--------------------------------------------------------------------------
%estimate spectral cross correlation matrix for each subband
%--------------------------------------------------------------------------
Pxx = zeros(size(X_des,3),size(X_des,3),size(X_des,1));
%easier case ->Y consider only noise components
% for idx_nu = 1:size(X_des,1)
%     Pxx(:,:,idx_nu) = cov(squeeze(X_int(idx_nu,:,:)));
% end
for idx_nu = 1:size(X_des,1)
    Pxx(:,:,idx_nu) = cov(squeeze(X_int(idx_nu,:,:)));
end
Pxx = Pxx./size(X,2);

sig.Pxx = Pxx;
%load hrtfs if required
if strcmp(cfg.design,'hrtf')
    load(cfg.path_hrirs);
    HRTF = fft(hrir,cfg.fs,1);
    %determine index of source direction    
%     idx_sourceDir = cfg.idx_sourcePosition(cfg.position(1));
end 

%--------------------------------------------------------------------------
%perform MVDR beamforming for each subband and frame
%--------------------------------------------------------------------------
%matrix for output blocks
Y = zeros(size(X,1), size(X,2));
Y_des = zeros(size(X,1), size(X,2));
Y_int = zeros(size(X,1), size(X,2));
H = zeros(size(X,3), size(X,1));

for idx_nu = 1:size(X,1)
    switch cfg.design
        case 'freefield'
            %create wavevector according to van Trees (2.25)
            kvec = - cfg.k_range(idx_nu) * [sind(cfg.look_elevation)*cosd(cfg.look_azimuth);...
                sind(cfg.look_elevation)*sind(cfg.look_azimuth);...
                cosd(cfg.look_elevation)];
            %create steering vector according to van Trees (2.28) for all
            %microphone positions
            v_k(:,idx_nu) = exp(-1i*kvec.'*[cfg.mic_pos.x; cfg.mic_pos.y; cfg.mic_pos.z]).';
        case 'hrtf'
            if idx_nu == 1
                v_k = HRTF(1,:,cfg.position(1)).';
            else
                v_k = HRTF(ceil(cfg.frange(idx_nu)),:,cfg.position(1)).';
            end
    end
    %compute beamforming weights (according to (6.74) in vanTrees - Optimum
    %Array Processing
    rho = 0;%0.00001; %regularization constant for diagonal loading
    %estimate filter coefficients
    W(:,idx_nu) = ((v_k(:,idx_nu)'*inv(Pxx(:,:,idx_nu)+rho*eye(cfg.nmic))) / ...
        (v_k(:,idx_nu)'*inv(Pxx(:,:,idx_nu)+rho*eye(cfg.nmic))*v_k(:,idx_nu))).';
    
    %perform beamforming frequency-band-wise
    Y(idx_nu,:) = W(:,idx_nu)'*squeeze(X(idx_nu,:,:)).';
    Y_des(idx_nu,:) = W(:,idx_nu)'*squeeze(X_des(idx_nu,:,:)).';
    Y_int(idx_nu,:) = W(:,idx_nu)'*squeeze(X_int(idx_nu,:,:)).';
end %for idx_nu

%create time-domain output signal
y = istft(Y, 128, 512, cfg.fs);
y_des = istft(Y_des, 128, 512, cfg.fs);
y_int = istft(Y_int, 128, 512, cfg.fs);
sig.v_k = v_k;
%--------------------------------------------------------------------------
%Set output signal y
%--------------------------------------------------------------------------
sig.y = y;
sig.Y = Y;
sig.y_des = y_des;
sig.y_int = y_int;
%--------------------------------------------------------------------------
end