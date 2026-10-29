# Creation-stall observation (base operator ee327075b1)

Captured: 2026-10-28T23:56:28Z

## Operator image
quay.io/example/hypershift@sha256:a8848bd5281ac07a23eb2f583f506e59aaa60702ff6aa0cb4530884479821839

## MachineDeployment status counters
replicas=3 ready=3 available=3 upToDate=0 updated=null generation=1 observedGeneration=1

## MachineSet status
name=test-cntrlplane-4826-r3-base-bptmg revision=1 replicas=3 available=3 ready=3

## NodePool rollout conditions
UpdatingVersion=True reason=AsExpected message=Updating version in progress. Target version: 5.0.0-rc.7
UpdatingPlatformMachineTemplate=True reason=AsExpected message=platform machine template update in progress. Target template: test-cntrlplane-4826-r3-base-776e47ca
Ready=True reason=Ready message=

## Node kubelet versions vs MD template version
test-cntrlplane-4826-r3-base-bptmg-b57gm	v1.36.5
test-cntrlplane-4826-r3-base-bptmg-l67fd	v1.36.5
test-cntrlplane-4826-r3-base-bptmg-zfmjc	v1.36.5
MD template version=5.0.0-rc.7
