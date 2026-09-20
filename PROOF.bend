import Base
import ./LAWS.bend as Laws

def Laws.segments_drop_empty():
  {==}

def Laws.classify_segments():
  {==}

def Laws.route_binds_param():
  {==}

def Laws.route_rejects_literal():
  {==}

def Laws.route_rejects_length():
  {==}

def Laws.wildcard_binds_tail():
  {==}

def Laws.wildcard_binds_empty():
  {==}

def Laws.shape_anonymizes():
  {==}

def Laws.shape_root():
  {==}

def Laws.mount_prefixes():
  {==}

def Laws.all_keeps_order():
  {==}

def Laws.conflicts_finds_duplicate():
  {==}

def Laws.conflicts_keeps_slash_apart():
  {==}

def Laws.conflicts_allows_methods():
  {==}

def Laws.conflicts_flags_wildcard_position():
  {==}

def Laws.has_slash_root():
  {==}

def Laws.strict_slash_gate():
  {==}

def Laws.redirect_target_keeps_query():
  {==}

def Laws.redirect_target_drops_all_slashes():
  {==}

def Laws.redirect_target_no_query():
  {==}

def Laws.head_falls_back_to_get():
  {==}

def Laws.explicit_head_wins():
  {==}

def Laws.head_needs_a_path_match():
  {==}

def Laws.allow_lists_methods():
  {==}

def Laws.allow_without_get_has_no_head():
  {==}

def Laws.miss_unknown_path():
  {==}

def Laws.options_star_lists_everything():
  {==}

def Laws.options_route_is_a_hit():
  {==}

def Laws.allow_header_set():
  {==}

def Laws.render_options():
  {==}


def Laws.method_roundtrip():
  {==}

def Laws.reason_ok():
  {==}

def Laws.reason_unknown():
  {==}

def Laws.byte_length_utf8():
  {==}

def Laws.split_head():
  {==}

def Laws.decode_plain():
  {==}

def Laws.decode_utf8():
  {==}

def Laws.decode_plus_in_query():
  {==}

def Laws.decode_plus_in_path():
  {==}

def Laws.decode_rejects_short():
  {==}

def Laws.decode_rejects_bad_hex():
  {==}

def Laws.decode_rejects_nul():
  {==}

def Laws.decode_rejects_overlong():
  {==}

def Laws.decode_rejects_lone_lead():
  {==}

def Laws.needs_decode_scan():
  {==}

def Laws.last_is_scan():
  {==}

def Laws.decode_rejects_surrogate():
  {==}

def Laws.path_decoded():
  {==}

def Laws.path_keeps_encoded_slash():
  {==}

def Laws.path_collapses_slashes():
  {==}

def Laws.path_resolves_dots():
  {==}

def Laws.path_root():
  {==}

def Laws.path_rejects_climb():
  {==}

def Laws.path_rejects_bad_escape():
  {==}

def Laws.path_absolute_form():
  {==}

def Laws.path_asterisk():
  {==}

def Laws.query_decoded():
  {==}

def Laws.query_rejects_bad_escape():
  {==}

def Laws.digits_strict():
  {==}

def Laws.digits_empty():
  {==}

def Laws.digits_value():
  {==}

def Laws.hex_value():
  {==}

def Laws.take_bytes_utf8():
  {==}

def Laws.take_bytes_short():
  {==}

def Laws.take_bytes_split_char():
  {==}

def Laws.chunked_decodes():
  {==}

def Laws.chunked_waits():
  {==}

def Laws.chunked_too_large():
  {==}

def Laws.framing_fixed():
  {==}

def Laws.framing_chunked():
  {==}

def Laws.framing_rejects_both():
  {==}

def Laws.framing_rejects_duplicate_length():
  {==}

def Laws.framing_rejects_folded_header():
  {==}

def Laws.parse_rejects_long_url():
  {==}

def Laws.parse_rejects_version():
  {==}

def Laws.keep_alive_default_11():
  {==}

def Laws.keep_alive_close_11():
  {==}

def Laws.keep_alive_default_10():
  {==}

def Laws.keep_alive_opt_in_10():
  {==}

def Laws.no_body_statuses():
  {==}

def Laws.render_head_only():
  {==}

def Laws.render_204_has_no_length():
  {==}

def Laws.arm_from_now():
  {==}

def Laws.arm_none_is_never():
  {==}

def Laws.arm_next_bumps_gen():
  {==}

def Laws.arm_due_after():
  {==}

def Laws.arm_not_due_before():
  {==}

def Laws.arm_disarmed_never_due():
  {==}

def Laws.arm_sleep_to_deadline():
  {==}

def Laws.arm_sleep_capped():
  {==}

def Laws.arm_sleep_disarmed():
  {==}

def Laws.arm_sleep_at_least_1():
  {==}

def Laws.step_is_shortest():
  {==}

def Laws.step_skips_zero():
  {==}

def Laws.step_all_zero():
  {==}

def Laws.tally_admits_open():
  {==}

def Laws.tally_refuses_draining():
  {==}

def Laws.tally_enter_counts():
  {==}

def Laws.tally_enter_draining_stays():
  {==}

def Laws.tally_leave_counts():
  {==}

def Laws.tally_drain_keeps_count():
  {==}

def Laws.tally_clear_when_drained():
  {==}

def Laws.tally_not_clear_in_flight():
  {==}

def Laws.tally_not_clear_open():
  {==}
