classdef slam_no_removal < handle
    %EKF_SLAM The EKF algorithm for SLAM
    
    properties
        x = zeros(3,1); % The estimated state vector
        P = 0.001*ones(3,3); % The estimated state covariance
        Q_0 = [0.0002118*100,0;0,0.05805*100]; % top left is u and bottom right is q
        sigq = 0.01;
        siglm = 0.01; % The covariance of landmark measurements
%         sign = 5*pi/180; % uncertainty in bearing
%         sigr = 0.1; % uncertainty in range
        sign = 0.01; % uncertainty in bearing
        sigr = 0.01; % uncertainty in range
        idx2num = []; % The map from state vector index to landmark id.
    end
    
    methods
        function input_velocity(obj, dt, lin_velocity, ang_velocity)
            % Perform the update step of the EKF. This involves updating
            % the state and covariance estimates using the input velocity,
            % the time step, and the covariance of the update step.
            
            % step 1: A and B
            A = eye(length(obj.x));
            A(1,3) = -dt*lin_velocity*sin(obj.x(3));
            A(2,3) = dt*lin_velocity*cos(obj.x(3));
            
            B = zeros(length(obj.x),2);
            B(1,1) = dt*cos(obj.x(3));
            B(2,1) = dt*sin(obj.x(3));
            B(3,2) = dt;
            
            % step 2: covariance prediction
%             obj.Q_0 = eye(2) * obj.sigq;

            obj.P = A * obj.P * A' + B * obj.Q_0 * B';
            
            % step 3: state prediction 
            obj.x(1:3) = f(obj.x(1:3), [lin_velocity; ang_velocity], dt);
            
        end
        
        function input_measurements(obj, ids, z)
            % Perform the innovation step of the EKF. This involves adding
            % new (not previously seen) landmarks to the state vector and
            % implementing the EKF innovation equations. You will need the
            % landmark measurements and you will need to be careful about
            % matching up landmark ids with their indices in the state
            % vector and covariance matrix.
            
            % step 4: augment with new landmarks (if applicable)
            if ~isempty(setdiff(ids, obj.idx2num))
                add_new_landmarks(obj, ids, z)
            end
            
            % step 5: compute output estimate z_hat and C
            x_h = obj.x(1);
            y_h = obj.x(2);
            theta_h = obj.x(3);
            
            z_hat = zeros(length(ids)*2,1);
            C = zeros(length(ids)*2, length(obj.x));
            
            for c = 1:length(ids)
                curr_id = ids(c);
                idx_x = 3 + find(obj.idx2num == curr_id)*2 - 1;
                idx_y = idx_x + 1;
                lx_i = obj.x(idx_x);
                ly_i = obj.x(idx_y);
                z_i = [ -cos(theta_h)*(x_h - lx_i) - sin(theta_h)*(y_h - ly_i) ;
                        sin(theta_h)*(x_h - lx_i) - cos(theta_h)*(y_h - ly_i)];
                z_hat(2*c-1: 2*c) = z_i;
                
                C(2*c-1:2*c, 1:2) = [-cos(theta_h), -sin(theta_h);
                                     sin(theta_h),  -cos(theta_h)];

                C(2*c-1:2*c, 3) = [sin(theta_h)*(x_h - lx_i) - cos(theta_h)*(y_h - ly_i);
                                   cos(theta_h)*(x_h - lx_i) + sin(theta_h)*(y_h - ly_i)];
                
                C(2*c-1:2*c, idx_x:idx_y) = [cos(theta_h),  sin(theta_h);
                                             -sin(theta_h), cos(theta_h)];
            end
            
            % step 6: kalman gain
            R = eye(length(ids)*2) * obj.siglm;
%             R = eye(length(ids)*2);
%             for c = 1:length(ids)/2
%                 R(2*c-1:2*c, 2*c-1:2*c) = [0.1 0; 0 0.01];
%             end
            
%             R = measurement_noise(obj,ids,z); 
            % when using this function, change prior to ~5   
            K = obj.P * C' * (C * obj.P * C' + R)^(-1);
            
            
            % step 7: covariance update
            obj.P = (eye(length(obj.x)) - K * C) * obj.P;
            
            % step 8: state update
            if ~isempty(z)
                obj.x = obj.x - K * (z_hat - z);
            end
        end
        
        function add_new_landmarks(obj, ids, z)
            % Add a new (not seen before) landmark to the state vector and
            % covariance matrix. You will need to associate the landmark's
            % id number with its index in the state vector.
            x_h = obj.x(1);
            y_h = obj.x(2);
            theta_h = obj.x(3);
            old_len = length(obj.x);
            
            % new lmks ordered in ascending order
            new_lmks = setdiff(ids, obj.idx2num);
            new_idx2num = zeros(1,length(obj.idx2num) + length(new_lmks));
            new_idx2num(1:length(obj.idx2num)) = obj.idx2num;
            new_idx2num(length(obj.idx2num)+1:end) = new_lmks;
            obj.idx2num = new_idx2num;
%             obj.idx2num = [obj.idx2num, new_lmks];
 
            new_state = zeros(old_len + length(new_lmks)*2,1);
            new_state(1:old_len) = obj.x;
            new_cov = eye(old_len + length(new_lmks)*2);
            new_cov(1:old_len, 1:old_len) = obj.P;
            
            for c = 1:length(new_lmks)
                curr_id = new_lmks(c);
                    idx = find(ids == curr_id);
                    z_i = [z(idx*2-1);z(idx*2)];
                    new_state(old_len + 2*c-1: old_len + 2*c) = [x_h + cos(theta_h)*z_i(1) - sin(theta_h)*z_i(2);
                                                                 y_h + sin(theta_h)*z_i(1) + cos(theta_h)*z_i(2)] ; % update this with formula
            end
            new_cov(old_len + 1: end, old_len + 1: end) = 1e10*eye(length(new_lmks) * 2);
            obj.x = new_state;
            obj.P = new_cov;
            
            
            
            
        end
        
        function [robot, cov] = output_robot(obj)
            % Suggested: output the part of the state vector and covariance
            % matrix corresponding only to the robot.
            robot = obj.x(1:3);
            cov = obj.P(1:3, 1:3);

        end
        
        function [landmarks, cov] = output_landmarks(obj)
            % Suggested: output the part of the state vector and covariance
            % matrix corresponding only to the landmarks.
            landmarks = obj.x(4:end);
            cov = obj.P(4:end, 4:end);
        end
        
    end
end

 % Jacobians and System Functions
 
function x1 = f(x0,w,dt)
    % integrate the input u from the state x0 to obtain x1.
    x1(1) = x0(1) + dt*cos(x0(3))*w(1);
    x1(2) = x0(2) + dt*sin(x0(3))*w(1);
    x1(3) = x0(3) + dt*w(2);
end

function R = measurement_noise(obj,ids,measurements)
    I = eye(2*length(ids));
    n = zeros(2*length(ids),1);
    I_m = eye(2*length(ids));
    for c = 1:length(ids)
        if mod(c,2) == 0
            I_m(c,c) = 0;
        end
    end
    
    for c = 1:length(ids)
        n_i = [measurements(2*c-1); measurements(2*c)];
        n_i = n_i / norm(n_i);
        n(2*c-1 : 2*c) = n_i;
    end
    R = obj.sign^2 * (I - (n*n'))* I_m * (I - (n*n')) + obj.sigr^2 * (n*n');
end