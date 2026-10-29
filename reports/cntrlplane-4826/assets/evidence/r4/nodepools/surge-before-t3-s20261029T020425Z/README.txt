Test-harness accommodation (not a change to the scenario under test)

T2 ran with spec.management.replace.rollingUpdate.maxSurge=1 (the helper default when the
head pool was created), which serialises replacements: 1474s wall clock for 3 workers.
For T3 and T6 the surge is raised to 3 so a 3-worker Replace rollout runs concurrently.
This does not alter the completion predicate under test; it only changes how many
replacement Machines are created at once.

Provenance note: before/machinedeployment.json was fetched from namespace "clusters" and is an
empty list; MachineDeployments for a HostedCluster live in the HCP namespace
(clusters-test-cntrlplane-4826-r4-hc). before/machinedeployments-from-t2-final.json is the
MachineDeployment list captured by the T2 final snapshot immediately before this surge change,
and shows revision 2 with only MachineSets rev 1 (0 replicas) and rev 2 (3 replicas).
