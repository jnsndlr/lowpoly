# From playable idea to merged change

## Quick mode

Jon and Paul can each build a feature on a branch and open a draft PR. During iteration, try the feature in the game or run the one check that answers the immediate question. Use an existing system when it already owns the behavior. For example, the HUD can show a fare computed by the simulation without maintaining its own fare table. Temporary shortcuts are fine on the branch. Identify any that would become a second source of truth if shipped.

## Merge mode

When the author asks to merge, their agent owns these steps:

1. Update the branch or combined stack against current main. Review the entire diff that will land. If several branches depend on one another, validate the combined change.
2. Clean up the touched paths. Remove temporary diagnostics, duplicated rules and abandoned experiments. Keep the change readable for the next person. Put unrelated cleanup in Linear if it has a specific cost.
3. For changed rules, add or update a focused regression check. Exercise failure cases that matter, such as a full berth, an impossible timetable or loading an existing save. For changes to appearance or feel, inspect the actual feature from a player camera.
4. From the repository root with Godot 4.7, run the headless import and a short game launch. Inspect output for script and resource errors. Run the relevant longer checks for the affected subsystem.

       godot --headless --editor --path . --import
       godot --headless --path . --quit-after 120

   For changes to loading or traffic, the existing diagnostics include:

       godot --headless --path . --fixed-fps 30 --script tools/vehicle_overlap_test.gd -- --seed=123 --frames=6000
       godot --headless --path . --fixed-fps 30 --script tools/vessel_soak_test.gd -- --seed=123 --frames=20000

   Read the overlap, grounding and stall summaries. If a finding also occurs on main, record the comparison and any change in severity. A successful process exit alone does not establish safe traffic.
5. Mark the PR ready. Check the CI runs configured for this repository, fix failures, and repeat affected checks on the final commit. When there is no hosted workflow, say so and record the local commands and results. For touch, performance or device-specific behavior, record the device and build actually checked, or identify the outstanding device check. If that check is essential to knowing whether the change works, keep the PR open.
6. Record the gameplay outcome, tested commit, validation results and remaining observations in the PR. Either author with write access can merge their own PR after these checks. If main moved in a way that affects the change, update and retest before merging. If a merge breaks main, restore working behavior promptly, then fix the underlying problem on a branch.

## When to coordinate

Give the other author a heads-up before changing a save format, a shared simulation contract, build or export settings, or a system they are actively editing. Coordinate migration and compatibility before landing changes that affect their branch. Routine features do not need a second human sign-off.

Paul leads integration and verification. Jon leads gameplay and art direction. The feature author owns merge cleanup. Either person can improve a shared system when there is a concrete gameplay or maintenance reason.
