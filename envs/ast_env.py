import copy
import ctypes
import random
from typing import Any, List, Tuple, TypedDict, TypeVar

import gym
import numpy as np
import numpy.typing as npt


class State(ctypes.Structure):
    pass


class ASTEnv(gym.Env):
    def __init__(
        self,
        max_num_nodes: int,
        num_node_descriptor: int,
        num_assignments: int,
        code_per_assignment: List[int],
        num_actions: int,
        assignment_dir: str,
        perturbation: int = 0,
        max_num_tests: int = 10,
        max_tree_length: int = 10000,
        max_num_vars: int = 10,
        seed: int = 0,
    ):
        super(ASTEnv, self).__init__()

        State._fields_ = [
            ("edges", (ctypes.c_int * (max_num_nodes * 3)) * 3),
            ("tests", (ctypes.c_int * max_num_tests) * 2),
            ("nodes", ctypes.c_int * max_num_nodes),
            ("starter", ctypes.c_int * max_num_nodes),
            ("permitted_actions", ctypes.c_int * (num_actions + max_num_vars * 2)),
            ("vars_in_scope", ctypes.c_int * max_num_vars),
            ("args_in_scope", ctypes.c_int * max_num_vars * 2),
            ("zast", ctypes.c_char * max_tree_length),
            ("cursor", ctypes.c_int),
            ("num_nodes", ctypes.c_int),
            ("num_edges", ctypes.c_int),
            ("num_tests", ctypes.c_int),
            ("num_vars", ctypes.c_int),
            ("num_args", ctypes.c_int),
            ("assignment", ctypes.c_int),
            ("code", ctypes.c_int),
        ]

        # Set action and observation space
        self.num_node_descriptor = num_node_descriptor
        self.max_num_nodes = max_num_nodes
        self.num_actions = num_actions
        self.max_num_vars = max_num_vars
        self.perturbation = perturbation

        # Plus one to account for -1
        node_nvec = (num_node_descriptor + max_num_vars + 1) * np.ones(max_num_nodes)
        edge_nvec = (max_num_nodes + 1) * np.ones((max_num_nodes * 3, 3))
        vars_nvec = (max_num_nodes + 1) * np.ones(max_num_vars)
        args_nvec = (max_num_nodes + 1) * np.ones((max_num_vars, 2))

        self.action_space = gym.spaces.Discrete(num_actions + max_num_vars)
        self.observation_space = gym.spaces.Dict(
            {
                "nodes": gym.spaces.MultiDiscrete(node_nvec),
                "edges": gym.spaces.MultiDiscrete(edge_nvec),
                "permitted_actions": gym.spaces.MultiBinary(
                    num_actions + max_num_vars * 2
                ),
                "starter": gym.spaces.MultiDiscrete(node_nvec),
                "cursor_position": gym.spaces.Discrete(max_num_nodes),
                "vars_in_scope": gym.spaces.MultiDiscrete(vars_nvec),
                "args_in_scope": gym.spaces.MultiDiscrete(args_nvec),
                "assignment": gym.spaces.Discrete(num_assignments),
            }
        )

        self.astclib = ctypes.CDLL(
            "/RL_env/clib/astclib.so"
        )  # Used to call C functions
        self.state = None

        self.code_per_assignment = code_per_assignment
        self.assignment_dir = assignment_dir

        self.astclib.init_c(ctypes.c_int(seed))

    def step(self, action: int):
        self.astclib.take_action(ctypes.byref(self.state), ctypes.c_int(action))
        reward = self.astclib.check_ast(ctypes.byref(self.state))

        done = False
        if reward == 1:
            done = True

        # Change state to Python dict
        state = self.get_state()

        return state, reward, done, {}

    def reset(self):
        assignment = self.observation_space.spaces["assignment"].sample()
        code = random.randint(0, self.code_per_assignment[assignment] - 1)

        self.state = State()
        self.astclib.init_assignment(
            ctypes.byref(self.state),
            bytes(self.assignment_dir, encoding="utf8"),
            ctypes.c_int(assignment),
            ctypes.c_int(code),
            ctypes.c_int(self.perturbation),
        )

        return self.get_state()

    def render(self, mode=None) -> None:
        print("Current state:")
        self.astclib.print_curr_state(ctypes.byref(self.state))

    def close(self) -> None:
        self.astclib.close_c()

    # Get Python dictionary for self.state
    def get_state(self):
        state = {
            "nodes": np.ctypeslib.as_array(self.state.nodes),
            "edges": np.ctypeslib.as_array(self.state.edges).reshape(-1, 3),
            "starter": np.ctypeslib.as_array(self.state.starter),
            "permitted_actions": np.ctypeslib.as_array(self.state.permitted_actions),
            "cursor_position": self.state.cursor,
            "vars_in_scope": np.ctypeslib.as_array(self.state.vars_in_scope),
            "args_in_scope": np.ctypeslib.as_array(self.state.args_in_scope).reshape(
                -1, 2
            ),
            "assignment": self.state.assignment,
        }

        return self.pad_states(state)

    def pad_states(self, state):
        for i in range(self.state.num_nodes, self.max_num_nodes):
            state["nodes"][i] = -1
            state["starter"][i] = -1

        for i in range(self.state.num_edges, self.max_num_nodes * 3):
            state["edges"][i][0] = -1

        for i in range(self.state.num_vars, self.max_num_vars):
            state["vars_in_scope"][i] = -1

        for i in range(self.state.num_args, self.max_num_vars):
            state["args_in_scope"][i][0] = -1

        return state

    def unpad_states(self, state):
        for i in range(self.max_num_nodes):
            if state["nodes"][i] == -1:
                state["nodes"] = state["nodes"][:i]
                state["starter"] = state["starter"][:i]
                break

        for i in range(self.max_num_nodes * 3):
            if state["edges"][i][0] == -1:
                state["edges"] = state["edges"][:i]
                break

        for i in range(self.max_num_vars):
            if state["vars_in_scope"][i] == -1:
                state["vars_in_scope"] = state["vars_in_scope"][:i]
                break

        for i in range(self.max_num_vars):
            if state["args_in_scope"][i][0] == -1:
                state["args_in_scope"] = state["args_in_scope"][:i]
                break

        return state
