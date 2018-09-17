# frozen_string_literal: true

require 'svmkit/base/base_estimator'
require 'svmkit/optimizer/nadam'

module SVMKit
  module LinearModel
    # SGDLinearEstimator is an abstract class for implementation of linear estimator
    # with mini-batch stochastic gradient descent optimization.
    # This class is used for internal process.
    class SGDLinearEstimator
      include Base::BaseEstimator

      # Initialize a linear estimator.
      #
      # @param reg_param [Float] The regularization parameter.
      # @param fit_bias [Boolean] The flag indicating whether to fit the bias term.
      # @param bias_scale [Float] The scale of the bias term.
      # @param max_iter [Integer] The maximum number of iterations.
      # @param batch_size [Integer] The size of the mini batches.
      # @param optimizer [Optimizer] The optimizer to calculate adaptive learning rate.
      #   If nil is given, Nadam is used.
      # @param random_seed [Integer] The seed value using to initialize the random generator.
      def initialize(reg_param: 1.0, fit_bias: false, bias_scale: 1.0,
                     max_iter: 1000, batch_size: 10, optimizer: nil, random_seed: nil)
        @params = {}
        @params[:reg_param] = reg_param
        @params[:fit_bias] = fit_bias
        @params[:bias_scale] = bias_scale
        @params[:max_iter] = max_iter
        @params[:batch_size] = batch_size
        @params[:optimizer] = optimizer
        @params[:optimizer] ||= Optimizer::Nadam.new
        @params[:random_seed] = random_seed
        @params[:random_seed] ||= srand
        @weight_vec = nil
        @bias_term = nil
        @rng = Random.new(@params[:random_seed])
      end

      private

      def partial_fit(x, y)
        # Expand feature vectors for bias term.
        samples = @params[:fit_bias] ? expand_feature(x) : x
        # Initialize some variables.
        n_samples, n_features = samples.shape
        rand_ids = [*0...n_samples].shuffle(random: @rng)
        weight = Numo::DFloat.zeros(n_features)
        optimizer = @params[:optimizer].dup
        # Optimization.
        @params[:max_iter].times do |_t|
          # Random sampling
          subset_ids = rand_ids.shift(@params[:batch_size])
          rand_ids.concat(subset_ids)
          sub_samples = samples[subset_ids, true]
          sub_targets = y[subset_ids]
          # Update weight.
          loss_gradient = calc_loss_gradient(sub_samples, sub_targets, weight)
          next if loss_gradient.ne(0.0).count.zero?
          weight = calc_new_weight(optimizer, sub_samples, weight, loss_gradient)
        end
        split_weight(weight)
      end

      def calc_loss_gradient(_x, _y, _weight)
        raise NotImplementedError, "#{__method__} has to be implemented in #{self.class}."
      end

      def calc_new_weight(optimizer, x, weight, loss_gradient)
        weight_gradient = x.transpose.dot(loss_gradient) / @params[:batch_size] + @params[:reg_param] * weight
        optimizer.call(weight, weight_gradient)
      end

      def expand_feature(x)
        n_samples = x.shape[0]
        Numo::NArray.hstack([x, Numo::DFloat.ones([n_samples, 1]) * @params[:bias_scale]])
      end

      def split_weight(weight)
        if @params[:fit_bias]
          [weight[0...-1].dup, weight[-1]]
        else
          [weight, 0.0]
        end
      end
    end
  end
end
