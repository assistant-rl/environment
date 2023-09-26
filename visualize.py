import os

import torch
import yaml
from run_logger import RunLogger, get_load_params

from agent.arguments import get_args_visualizer
from agent.envs import PLEnv
from agent.policy import GNNPolicy


def main(save_dir, log_name, run_id):
    print(f"Visualizing {log_name}...")
    
    # Get save directory
    save_dir = os.path.join(save_dir, log_name)
    with open(os.path.join(save_dir, "params.yaml"), 'r') as f:
        params = yaml.safe_load(f)

    torch.manual_seed(params["seed"])
    torch.cuda.manual_seed_all(params["seed"])

    if params["cuda"] and torch.cuda.is_available() and params["cuda_deterministic"]:
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True

    torch.set_num_threads(1)
    device = torch.device("cuda" if params["cuda"] else "cpu")

    params["num_processes"] = 1
    env_kwargs = params["env"] # used to be "eval"
    env_kwargs["max_episode_steps"] = params["env"]["max_episode_steps"]
    env = PLEnv.make_vec_envs(
        params["seed"], params["num_processes"], device, render=True, **env_kwargs
    )

    base_kwargs = params["base"]
    actor_critic = GNNPolicy(
        env.get_attr("orig_obs_space")[0],
        env.get_attr("action_space")[0],
        env.get_attr("num_actions")[0],
        base_kwargs=base_kwargs,
        device=device,
        done_action = params['env']['done_action'],
    )
    actor_critic.to(device)
    actor_critic.load_state_dict(torch.load(os.path.join(save_dir, 'params.pt'))[0])
    actor_critic.eval()

    obs = env.reset()
    env.render()
    step = 0 
    stop_on_update = False 
    while True:
        with torch.no_grad():
            (_, action, _, _,) = actor_critic.act(
                obs,
                None,
                None,
            )
        step +=1
        print(f'step: {step}')
        print(f"Action: {action}")
        if stop_on_update: breakpoint() # to allow manual change, action[0] = n 
        # if needed add python input l
        obs, reward, done, info = env.step(action.reshape((-1,)))

        if done[0]:
            print(f"Reward: {info[0]['episode']['r']}")
            step = 0 
            print()
            print(f'step: {step}')
            # breakpoint()
            if info[0]["episode"]["r"] == 0:
                print('failed')
                breakpoint()

            # breakpoint()
            print("---------------Environment reset---------------")

        env.render()
        print()


if __name__ == "__main__":
    args = get_args_visualizer()

    main(args.save_dir, args.log_name, args.run_id)
