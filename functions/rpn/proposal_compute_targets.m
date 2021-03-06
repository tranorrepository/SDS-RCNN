function [bbox_targets, overlaps, targets ] = proposal_compute_targets(conf, gt_rois, gt_ignores, gt_labels, ex_rois, image_roidb, im_scale)
    
    % output: bbox_targets
    %   positive: [class_label, regression_label]
    %   ingore: [0, zero(regression_label)]
    %   negative: [-1, zero(regression_label)]

    gt_rois_full = gt_rois;
    gt_rois = gt_rois(gt_ignores~=1, :);
    
    if isempty(gt_rois_full)
        overlaps = zeros(size(ex_rois, 1), 1, 'double');
        overlaps = sparse(overlaps);
        targets = uint8(zeros(size(ex_rois, 1), 1));
    else

        ex_gt_full_overlaps = boxoverlap(ex_rois, gt_rois_full);        
        [overlaps, targets] = max(ex_gt_full_overlaps, [], 2); 
        overlaps = sparse(double(overlaps));

    end

    if isempty(gt_rois)
        bbox_targets = zeros(size(ex_rois, 1), 5, 'double');
        bbox_targets(:, 1) = -1;
        bbox_targets = sparse(bbox_targets);
        return;
    end
    
    % ensure gt_labels is in single
    gt_labels = single(gt_labels);
    assert(all(gt_labels > 0));

    ex_gt_overlaps = boxoverlap(ex_rois, gt_rois); % for fg
    ex_gt_full_overlaps = boxoverlap(ex_rois, gt_rois_full);  % for bg
    
    % drop anchors which run out off image boundaries, if necessary
    contained_in_image = is_contain_in_image(ex_rois, round(image_roidb.im_size * im_scale));

    % for each ex_rois(anchors), get its max overlap with all gt_rois
    [ex_max_overlaps, ex_assignment] = max(ex_gt_overlaps, [], 2); % for fg
    [ex_full_max_overlaps, ex_full_assignment] = max(ex_gt_full_overlaps, [], 2); % for bg
    
    % for each gt_rois, get its max overlap with all ex_rois(anchors), the
    % ex_rois(anchors) are recorded in gt_assignment
    % gt_assignment will be assigned as positive 
    % (assign a rois for each gt at least)
    [gt_max_overlaps, gt_assignment] = max(ex_gt_overlaps, [], 1);
    
    % ex_rois(anchors) with gt_max_overlaps maybe more than one, find them
    % as (gt_best_matches)
    [gt_best_matches, gt_ind] = find(bsxfun(@eq, ex_gt_overlaps, [gt_max_overlaps]));
    
    % Indices of examples for which we try to make predictions
    % both (ex_max_overlaps >= conf.fg_thresh) and gt_best_matches are
    % assigned as positive examples
    fg_inds = unique([find(ex_max_overlaps >= conf.fg_thresh); gt_best_matches]);
        
    % Indices of examples for which we try to used as negtive samples
    % the logic for assigning labels to anchors can be satisfied by both the positive label and the negative label
    % When this happens, the code gives the positive label precedence to
    % pursue high recall
    bg_inds = setdiff(find(ex_full_max_overlaps < conf.bg_thresh_hi & ex_full_max_overlaps >= conf.bg_thresh_lo), fg_inds);
    
    contained_in_image_ind = find(contained_in_image);
    fg_inds = intersect(fg_inds, contained_in_image_ind);
                
    % Find which gt ROI each ex ROI has max overlap with:
    % this will be the ex ROI's gt target
    target_rois = gt_rois(ex_assignment(fg_inds), :);
    src_rois = ex_rois(fg_inds, :);
    
    % we predict regression_label which is generated by an un-linear
    % transformation from src_rois and target_rois
    [regression_label] = fast_rcnn_bbox_transform(src_rois, target_rois);
    
    bbox_targets = zeros(size(ex_rois, 1), 5, 'double');
    bbox_targets(fg_inds, :) = [gt_labels(ex_assignment(fg_inds)), regression_label];
    bbox_targets(bg_inds, 1) = -1;
    
    if 0 % debug
        %%%%%%%%%%%%%%
        im = imread(image_roidb.image_path);
        [im, im_scale] = prep_im_for_blob(im, conf.image_means, conf.scales, conf.max_size);
        imshow(mat2gray(im));
        hold on;
        cellfun(@(x) rectangle('Position', RectLTRB2LTWH(x), 'EdgeColor', 'r'), ...
                   num2cell(src_rois, 2));
        cellfun(@(x) rectangle('Position', RectLTRB2LTWH(x), 'EdgeColor', 'g'), ...
                   num2cell(target_rois, 2));
        hold off;
        %%%%%%%%%%%%%%
    end
    
    bbox_targets = sparse(bbox_targets);
end

function contained = is_contain_in_image(boxes, im_size)
    contained = boxes >= 1 & bsxfun(@le, boxes, [im_size(2), im_size(1), im_size(2), im_size(1)]);
    
    contained = all(contained, 2);
end
