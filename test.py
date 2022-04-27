from envs.ast_env import ASTEnv


def main():
    env = ASTEnv(1, [1])

    for i in range(5):
        print("-----------------------")
        print(f"Timestep: {i + 1}")

        obs = env.reset()
        print("Reset environment.")
        print(f"Assignment index: {env.get_state()['assignment']}")
        env.render()
        print()

        done = False
        count = 0
        while not done and count < 20:
            action = -1
            # TODO: change this to policy + permitted actions
            for i in range(len(obs["permitted_actions"])):
                if obs["permitted_actions"][i] == 1:
                    action = i
                    break

            print(f"Action taken: {action}")

            obs, reward, done, info = env.step(action)

            env.render()

            print(f"Reward: {reward}\n")

            count += 1
        if count == 20:
            print("Too many steps")
        else:
            print("Done!")
    env.close()


if __name__ == "__main__":
    main()
