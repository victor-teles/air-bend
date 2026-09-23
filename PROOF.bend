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

def Laws.json_parse_object():
  {==}

def Laws.json_parse_empty_containers():
  {==}

def Laws.json_render_escapes():
  {==}

def Laws.json_render_nested():
  {==}

def Laws.json_parse_unicode_escape():
  {==}

def Laws.json_parse_surrogate_pair():
  {==}

def Laws.json_rejects_lone_surrogate():
  {==}

def Laws.json_rejects_raw_control():
  {==}

def Laws.json_rejects_trailing_comma():
  {==}

def Laws.json_rejects_mismatched_bracket():
  {==}

def Laws.json_rejects_trailing_garbage():
  {==}

def Laws.json_rejects_depth():
  {==}

def Laws.json_accepts_depth_64():
  {==}

def Laws.json_number_lexeme():
  {==}

def Laws.json_rejects_bad_numbers():
  {==}

def Laws.json_rejects_bad_literal():
  {==}

def Laws.json_get_first_key():
  {==}

def Laws.json_u32_strict():
  {==}

def Laws.request_json_parses():
  {==}

def Laws.request_json_needs_content_type():
  {==}

def Laws.response_of_json():
  {==}

def Laws.split_seq_all_pieces():
  {==}

def Laws.split_seq_all_no_hit():
  {==}

def Laws.query_all_repeats():
  {==}

def Laws.query_all_absent():
  {==}

def Laws.form_decodes():
  {==}

def Laws.form_needs_media_type():
  {==}

def Laws.form_all_repeats():
  {==}

def Laws.media_type_strips_params():
  {==}

def Laws.boundary_quoted():
  {==}

def Laws.boundary_wrong_type():
  {==}

def Laws.multipart_two_parts():
  {==}

def Laws.multipart_missing_blank():
  {==}

def Laws.multipart_unterminated():
  {==}

def Laws.multipart_wrong_type():
  {==}

def Laws.multipart_field_and_file():
  {==}

def Laws.cookie_parses():
  {==}

def Laws.cookie_missing():
  {==}

def Laws.cookies_in_order():
  {==}

def Laws.negotiate_thousandths():
  {==}

def Laws.negotiate_q_order():
  {==}

def Laws.negotiate_wildcard():
  {==}

def Laws.negotiate_specific_wins():
  {==}

def Laws.negotiate_zero_excludes():
  {==}

def Laws.negotiate_absent_takes_first():
  {==}

def Laws.negotiate_nothing():
  {==}

def Laws.negotiate_language_prefix():
  {==}

def Laws.negotiate_earliest_on_tie():
  {==}

def Laws.client_ip_untrusted():
  {==}

def Laws.client_ip_rightmost():
  {==}

def Laws.client_ip_forwarded():
  {==}

def Laws.client_ip_absent():
  {==}

def Laws.scheme_forwarded():
  {==}

def Laws.host_header():
  {==}

def Laws.accepts_language_header():
  {==}

def Laws.fnv1a_known():
  {==}

def Laws.hex_show_pads():
  {==}

def Laws.etag_shape():
  {==}

def Laws.etag_counts_bytes():
  {==}

def Laws.with_etag_headers():
  {==}

def Laws.parse_range_forms():
  {==}

def Laws.parse_range_clamps():
  {==}

def Laws.parse_range_bad():
  {==}

def Laws.conditional_304():
  {==}

def Laws.conditional_weak_and_list():
  {==}

def Laws.conditional_star():
  {==}

def Laws.conditional_miss():
  {==}

def Laws.ranged_206():
  {==}

def Laws.ranged_suffix():
  {==}

def Laws.ranged_416():
  {==}

def Laws.ranged_multibyte_416():
  {==}

def Laws.ranged_passes_other_methods():
  {==}

def Laws.chunk_frames():
  {==}

def Laws.chunk_size_is_hex():
  {==}

def Laws.last_chunk_ends():
  {==}

def Laws.sse_event_format():
  {==}

def Laws.sse_data_format():
  {==}

def Laws.cookie_render_defaults():
  {==}

def Laws.cookie_render_full():
  {==}

def Laws.cookie_same_site_none_forces_secure():
  {==}

def Laws.cookie_session_has_no_age():
  {==}

def Laws.expire_cookie_line():
  {==}

def Laws.render_two_cookies_in_order():
  {==}

def Laws.with_type_adds_charset():
  {==}

def Laws.with_type_keeps_binary():
  {==}

def Laws.with_type_keeps_params():
  {==}

def Laws.send_infers_html():
  {==}

def Laws.send_infers_json():
  {==}

def Laws.send_infers_text():
  {==}

def Laws.see_other_status():
  {==}

def Laws.see_other_location():
  {==}

def Laws.reasons_added():
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

def Laws.local_round_trip():
  {==}

def Laws.local_absent():
  {==}

def Laws.local_keeps_params():
  {==}

def Laws.wrap_keeps_patterns():
  {==}

def Laws.wrap_keeps_conflicts():
  {==}

def Laws.error_status_not_found():
  {==}

def Laws.error_status_other():
  {==}

def Laws.error_reason_gone():
  {==}

def Laws.fail_carries_status():
  {==}

def Laws.fail_reads_back():
  {==}

def Laws.whole_has_no_error():
  {==}

def Laws.settle_prod_hides_detail():
  {==}

def Laws.settle_dev_shows_detail():
  {==}

def Laws.settle_keeps_type():
  {==}

def Laws.not_found_is_failed():
  {==}

def Laws.not_found_renders_same():
  {==}

def Laws.json_prod_shape():
  {==}

def Laws.json_dev_shape():
  {==}

def Laws.plain_dev_shape():
  {==}

def Laws.inherit_keeps_allow():
  {==}

def Laws.inherit_renderer_wins():
  {==}

def Laws.inherit_keeps_cookies():
  {==}

def Laws.default_header_sets_absent():
  {==}

def Laws.default_header_keeps_present():
  {==}

def Laws.cors_any_allows():
  {==}

def Laws.cors_list_exact():
  {==}

def Laws.cors_list_hit():
  {==}

def Laws.cors_star_without_creds():
  {==}

def Laws.cors_echo_with_creds():
  {==}

def Laws.cors_echo_with_list():
  {==}

def Laws.cors_vary_appends():
  {==}

def Laws.cors_vary_once():
  {==}

def Laws.cors_preflight_echoes_headers():
  {==}

def Laws.cors_preflight_status():
  {==}

def Laws.cors_is_preflight():
  {==}

def Laws.cors_plain_options_not_preflight():
  {==}

def Laws.shield_default_nosniff():
  {==}

def Laws.shield_handler_wins():
  {==}

def Laws.shield_hsts_opt_in():
  {==}

def Laws.shield_with_hsts():
  {==}

def Laws.shield_with_header_replaces():
  {==}

def Laws.static_safe_plain():
  {==}

def Laws.static_refuses_dotdot():
  {==}

def Laws.static_refuses_dot():
  {==}

def Laws.static_refuses_slash():
  {==}

def Laws.static_refuses_backslash():
  {==}

def Laws.static_hides_dotfiles():
  {==}

def Laws.static_refuses_empty():
  {==}

def Laws.static_mime_html():
  {==}

def Laws.static_mime_upper():
  {==}

def Laws.static_mime_last_dot():
  {==}

def Laws.static_mime_dotted_dir():
  {==}

def Laws.static_index_root():
  {==}

def Laws.static_index_dir():
  {==}

def Laws.static_file():
  {==}

def Laws.log_safe_id_plain():
  {==}

def Laws.log_safe_id_empty():
  {==}

def Laws.log_safe_id_space():
  {==}

def Laws.log_safe_id_long():
  {==}

def Laws.log_safe_id_max():
  {==}

def Laws.log_hex_id_len():
  {==}

def Laws.log_hex_id_padded():
  {==}

def Laws.log_line_escapes():
  {==}

def Laws.store_ns_default_empty():
  {==}

def Laws.request_store_seeded_none():
  {==}

def Laws.rate_epoch():
  {==}

def Laws.rate_tick_same_window():
  {==}

def Laws.rate_tick_new_window():
  {==}

def Laws.rate_tick_other_key():
  {==}

def Laws.rate_reset_in_min_one():
  {==}

def Laws.rate_reset_in_full():
  {==}

def Laws.rate_refuse_status():
  {==}

def Laws.rate_refuse_retry_after():
  {==}

def Laws.rate_refuse_is_failed():
  {==}

def Laws.rate_remaining_floor():
  {==}

def Laws.rate_remaining_counts():
  {==}

def Laws.session_encode_decode():
  {==}

def Laws.session_decode_garbage():
  {==}

def Laws.session_alive_fresh():
  {==}

def Laws.session_dead_old():
  {==}

def Laws.session_dead_unseen():
  {==}

def Laws.session_dead_future():
  {==}

def Laws.session_sweep_keeps_live():
  {==}

def Laws.session_cookie_defaults():
  {==}

def Laws.session_cookie_secure():
  {==}

def Laws.schema_str_ok():
  {==}

def Laws.schema_str_wrong():
  {==}

def Laws.schema_obj_missing():
  {==}

def Laws.schema_obj_optional():
  {==}

def Laws.schema_obj_unknown():
  {==}

def Laws.schema_obj_open():
  {==}

def Laws.schema_order():
  {==}

def Laws.schema_arr_index():
  {==}

def Laws.schema_enum():
  {==}

def Laws.schema_nested_path():
  {==}

def Laws.schema_strict_int():
  {==}

def Laws.schema_lenient_int():
  {==}

def Laws.schema_lenient_bad_int():
  {==}

def Laws.schema_422_body():
  {==}

def Laws.view_lex_text_var():
  {==}

def Laws.view_lex_raw():
  {==}

def Laws.view_lex_section():
  {==}

def Laws.view_lex_unterminated():
  {==}

def Laws.view_escapes():
  {==}

def Laws.view_raw():
  {==}

def Laws.view_missing_empty():
  {==}

def Laws.view_list():
  {==}

def Laws.view_inverted():
  {==}

def Laws.view_truthy_object():
  {==}

def Laws.view_stack_lookup():
  {==}

def Laws.view_dotted():
  {==}

def Laws.view_nested_sections():
  {==}

def Laws.view_unclosed_section():
  {==}

def Laws.view_false_skips():
  {==}

def Laws.test_get_raw():
  {==}

def Laws.test_post_length():
  {==}

def Laws.test_with_header():
  {==}

def Laws.refusal_render():
  {==}

def Laws.refusal_unchanged():
  {==}

def Laws.test_takes_body_by_length():
  {==}

def Laws.test_refuses_long_head():
  {==}

def Laws.test_refuses_long_body():
  {==}

def Laws.test_refuses_short_body():
  {==}

def Laws.test_refuses_unended_head():
  {==}

def Laws.test_refuses_parse():
  {==}
