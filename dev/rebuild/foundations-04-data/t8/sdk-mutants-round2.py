TITLE = "be-sdk-go alpha.81 in progress (item 4 T8b), round 2: the survivor, after the test checks the ready line's phase"
BUILD = ['go', 'vet', '-tags', 'integration', './launcher/', './shell/', './internal/host/', './httpx/']
TEST = ['go', 'test', '-count=1', '-p', '1', '-tags', 'integration', '-run', 'TestRecoveryPhases|TestAShellInRecovery', './launcher/', './shell/']
MUTANTS = [('internal/host/member.go', '\tif phase := m.Phase(); phase != "" {\n\t\tm.SetState(RecoveryReady)', '\tif phase := m.Phase(); phase == "x" {\n\t\tm.SetState(RecoveryReady)', 'a member in a phase is plainly ready')]
