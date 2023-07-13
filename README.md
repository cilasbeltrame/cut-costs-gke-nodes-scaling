# cut-costs-gke-nodes-scaling

The script/workflows are divided into:

1. Bash script to scale up and down k8s nodes(to avoid mistakes, there is a condition that is either plan or apply).
2. One reusable workflow that can be used either manually in an interactive way or be called with schedule settings from another workflow. The workflow able to scale down and up any env, in case this is a problem we can restrict that just for some env and lower envs for instance.
3. Two scheduled workflows to scale down and up some env nodes with the following time: 8pm(scale down) and 6 am(scale up), just a reminder that cron from gihub actions is in UTC. To remove a schedule we can remove/comment the workflow.
