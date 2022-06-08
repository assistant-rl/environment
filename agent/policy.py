from typing import List

import gym
import ipdb
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch_geometric.nn as gnn
from gym.spaces.utils import unflatten

from agent.base import CNNBase, GNNBase, MLPBase
from agent.distributions import Bernoulli, Categorical, CategoricalAction, DiagGaussian
from agent.utils import batch_unflatten, init


class Policy(nn.Module):
    def __init__(self, obs_space, action_space, base=None, base_kwargs=None):
        super(Policy, self).__init__()
        if base_kwargs is None:
            base_kwargs = {}
        if base is None:
            if len(obs_space.shape) == 3:
                base = CNNBase
            elif len(obs_space.shape) == 1:
                base = MLPBase
            else:
                raise NotImplementedError

        self.base = base(obs_space.shape[0], **base_kwargs)

        if action_space.__class__.__name__ == "Discrete":
            num_outputs = action_space.n
            self.dist = Categorical(self.base.output_size, num_outputs)
        elif action_space.__class__.__name__ == "Box":
            num_outputs = action_space.shape[0]
            self.dist = DiagGaussian(self.base.output_size, num_outputs)
        elif action_space.__class__.__name__ == "MultiBinary":
            num_outputs = action_space.shape[0]
            self.dist = Bernoulli(self.base.output_size, num_outputs)
        else:
            raise NotImplementedError

    @property
    def is_recurrent(self):
        return self.base.is_recurrent

    @property
    def recurrent_hidden_state_size(self):
        """Size of rnn_hx."""
        return self.base.recurrent_hidden_state_size

    def forward(self, inputs, rnn_hxs, masks):
        raise NotImplementedError

    def act(self, inputs, rnn_hxs, masks, deterministic=False):
        value, actor_features, rnn_hxs = self.base(inputs, rnn_hxs, masks)
        dist = self.dist(actor_features)

        if deterministic:
            action = dist.mode()
        else:
            action = dist.sample()

        action_log_probs = dist.log_probs(action)

        return value, action, action_log_probs, rnn_hxs

    def get_value(self, inputs, rnn_hxs, masks):
        value, _, _ = self.base(inputs, rnn_hxs, masks)
        return value

    def evaluate_actions(self, inputs, rnn_hxs, masks, action):
        value, actor_features, rnn_hxs = self.base(inputs, rnn_hxs, masks)
        dist = self.dist(actor_features)

        action_log_probs = dist.log_probs(action)
        dist_entropy = dist.entropy().mean()

        return value, action_log_probs, dist_entropy, rnn_hxs


class GNNPolicy(Policy):
    def __init__(self, env: gym.Env, base_kwargs=None):
        super(Policy, self).__init__()

        self.env = env

        if base_kwargs is None:
            base_kwargs = {}
        self.base = GNNBase(**base_kwargs)

        num_outputs = env.action_space.n
        self.dist = CategoricalAction(self.base.output_size, num_outputs)

        self.empty_obs_dict = {}
        for key in self.env.observation_space:
            self.empty_obs_dict[key] = []

    def unflatten_input(self, input):
        input_dict = self.empty_obs_dict

        for i in range(input.shape[0]):
            datum = unflatten(self.env.observation_space, input[i])
            datum = self.env.unpad_states(datum)

            for key, value in datum.items():
                input_dict[key].append(value)

        return input_dict

    def act(self, inputs, rnn_hxs, masks, deterministic=False):
        # Unflatten the input

        value, actor_features, rnn_hxs = self.base(inputs, rnn_hxs, masks)
        if self.dist_mask:
            # TODO: batch
            dist = self.dist(
                actor_features, self.env.unwrap(inputs)["permitted_actions"]
            )
        else:
            dist = self.dist(actor_features)

        if deterministic:
            action = dist.mode()
        else:
            action = dist.sample()

        action_log_probs = dist.log_probs(action)

        return value, action, action_log_probs, rnn_hxs
