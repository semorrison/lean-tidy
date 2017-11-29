-- Copyright (c) 2017 Scott Morrison. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.
-- Authors: Scott Morrison

import ..loop_detection
import ..profiling

open tactic

meta instance loop_detecting_and_profiling_coercion { α : Type } : has_coe (interaction_monad tactic_state α) (interaction_monad ((tactic_state × invocation_count) × loop_detection_state) α) :=
⟨ instrument_for_loop_detection ∘ profiling_tactic_coercion.coe ⟩ 

-- TODO can we have some way to run tests, without producing output in leanpkg?

-- lemma looping_and_profiling_at_the_same_time_test_1 : true :=
-- begin
-- profiling $ (detect_looping $ triv),
-- end

-- lemma looping_and_profiling_at_the_same_time_test_2 : true :=
-- begin
-- success_if_fail { profiling $ detect_looping $ skip >> skip },
-- triv
-- end

-- lemma looping_and_profiling_at_the_same_time_test_3 : 1 = 1 :=
-- begin
-- success_if_fail { profiling $ detect_looping $ interactive_simp >> skip >> skip }, -- failed, with 2 invocations
-- simp
-- end