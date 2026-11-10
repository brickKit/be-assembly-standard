TITLE = "infra/authz 3.0.46 E4e: records bound to appointments"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TestAppointmentBindings", "./itest/"]
A = "internal/employment/appointments.go"
C = "internal/effectpoint/closure.go"
# HoldingsOf's filter by the facts last applied (between the source's change and the closure) is not mutated: the
# closure follows within the job's latency, and no step of the test can hold the job back to look in between. The
# link's state is checked twice on purpose (the facts' query takes active links only; the judgement reads the link's
# projected state again, at D_src_read): mutant 3 removed the second alone, did not build, and is not rewritten: each
# layer alone is equivalent
MUTANTS = [
    ("internal/view/view.go", "\t\tif b.Appointment != \"\" && !bound[employment.Binding{Appointment: b.Appointment, Account: b.Grantee}] {",
     "\t\tif false && b.Appointment != \"\" && !bound[employment.Binding{Appointment: b.Appointment, Account: b.Grantee}] {",
     "the view leaves out a grant whose binding does not hold"),
    (A, "out[b] = state(b.Appointment) == \"active\" && state(f.Link) == \"active\"",
     "out[b] = state(b.Appointment) != \"ended\" && state(f.Link) == \"active\"", "a planned appointment gives nothing yet"),
    (A, "out[b] = state(b.Appointment) == \"active\" && state(f.Link) == \"active\"",
     "out[b] = state(b.Appointment) == \"active\"", "an unlinked account gets nothing through the appointment"),
    (A, "\tcase f.Link == \"\":\n\t\treturn core.Disproven, \"the account is not linked to the appointment's employee\", nil",
     "\tcase false:\n\t\treturn core.Disproven, \"the account is not linked to the appointment's employee\", nil",
     "only an account linked to the appointment's employee is bound"),
    (A, "\tcase f.State != \"planned\" && f.State != \"active\":", "\tcase false:", "an ended appointment is never bound"),
    (C, "\t\tadd(\"account\", b.Grantee, \"eligibility\")\n\t\tadd(\"appointment\", b.Appointment, \"eligibility\")",
     "\t\tadd(\"account\", b.Grantee, \"eligibility\")", "a grant's appointment is indexed as its source"),
    (A, "\tcase f.Kind == KindLink && f.State == \"ended\" && f.Was != \"ended\":", "\tcase false:",
     "an ended link closes what the account held through the employee's appointments"),
    (A, "\tcase f.Kind == KindAppointment && f.State != f.Was && f.Was != \"\":", "\tcase false && f.Kind == KindAppointment:",
     "an appointment that moved is closed"),
    (C, "if w.limits.Of(b.Unit) == nil || w.Ended[b.Holder] || w.Unbound[employment.Binding{Appointment: b.Appointment, Account: b.Holder}] {",
     "if w.limits.Of(b.Unit) == nil || w.Ended[b.Holder] {", "a holding bound to an ended binding is booked ended"),
]
