#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/spinner_helpers.sh"

# delimiters
d=$'\t'
delimiter=$'\t'

# if "quiet" script produces no output
SCRIPT_OUTPUT="$1"

grouped_sessions_format() {
	local format
	format+="#{session_grouped}"
	format+="${delimiter}"
	format+="#{session_group}"
	format+="${delimiter}"
	format+="#{session_id}"
	format+="${delimiter}"
	format+="#{session_name}"
	echo "$format"
}

pane_format() {
	local format
	format+="pane"
	format+="${delimiter}"
	format+="#{session_name}"
	format+="${delimiter}"
	format+="#{window_index}"
	format+="${delimiter}"
	format+="#{window_active}"
	format+="${delimiter}"
	format+=":#{window_flags}"
	format+="${delimiter}"
	format+="#{pane_index}"
	format+="${delimiter}"
	format+="#{pane_title}"
	format+="${delimiter}"
	format+=":#{pane_current_path}"
	format+="${delimiter}"
	format+="#{pane_active}"
	format+="${delimiter}"
	format+="#{pane_current_command}"
	format+="${delimiter}"
	format+="#{pane_pid}"
	format+="${delimiter}"
	format+="#{history_size}"
	echo "$format"
}

window_format() {
	local format
	format+="window"
	format+="${delimiter}"
	format+="#{session_name}"
	format+="${delimiter}"
	format+="#{window_index}"
	format+="${delimiter}"
	format+=":#{window_name}"
	format+="${delimiter}"
	format+="#{window_active}"
	format+="${delimiter}"
	format+=":#{window_flags}"
	format+="${delimiter}"
	format+="#{window_layout}"
	echo "$format"
}

state_format() {
	local format
	format+="state"
	format+="${delimiter}"
	format+="#{client_session}"
	format+="${delimiter}"
	format+="#{client_last_session}"
	echo "$format"
}

dump_panes_raw() {
	tmux list-panes -a -F "$(pane_format)"
}

dump_windows_raw(){
	tmux list-windows -a -F "$(window_format)"
}

toggle_window_zoom() {
	local target="$1"
	tmux resize-pane -Z -t "$target"
}

_save_command_strategy_file() {
	local save_command_strategy="$(get_tmux_option "$save_command_strategy_option" "$default_save_command_strategy")"
	local strategy_file="$CURRENT_DIR/../save_command_strategies/${save_command_strategy}.sh"
	local default_strategy_file="$CURRENT_DIR/../save_command_strategies/${default_save_command_strategy}.sh"
	if [ -e "$strategy_file" ]; then # strategy file exists?
		echo "$strategy_file"
	else
		echo "$default_strategy_file"
	fi
}

pane_full_command() {
	local pane_pid="$1"
	local strategy_file="$(_save_command_strategy_file)"
	# execute strategy script to get pane full command
	$strategy_file "$pane_pid"
}

number_nonempty_lines_on_screen() {
	local pane_id="$1"
	tmux capture-pane -pJ -t "$pane_id" |
		sed '/^$/d' |
		wc -l |
		sed 's/ //g'
}

# tests if there was any command output in the current pane
pane_has_any_content() {
	local pane_id="$1"
	local history_size="$(tmux display -p -t "$pane_id" -F "#{history_size}")"
	local cursor_y="$(tmux display -p -t "$pane_id" -F "#{cursor_y}")"
	# doing "cheap" tests first
	[ "$history_size" -gt 0 ] || # history has any content?
		[ "$cursor_y" -gt 0 ] || # cursor not in first line?
		[ "$(number_nonempty_lines_on_screen "$pane_id")" -gt 1 ]
}

capture_pane_contents() {
	local pane_id="$1"
	local start_line="-$2"
	local pane_contents_area="$3"
	if pane_has_any_content "$pane_id"; then
		if [ "$pane_contents_area" = "visible" ]; then
			start_line="0"
		fi
		# the printf hack below removes *trailing* empty lines
		printf '%s\n' "$(tmux capture-pane -epJ -S "$start_line" -t "$pane_id")" > "$(pane_contents_file "save" "$pane_id")"
	fi
}

get_active_window_index() {
	local session_name="$1"
	tmux list-windows -t "$session_name" -F "#{window_flags} #{window_index}" |
		awk '$1 ~ /\*/ { print $2; }'
}

get_alternate_window_index() {
	local session_name="$1"
	tmux list-windows -t "$session_name" -F "#{window_flags} #{window_index}" |
		awk '$1 ~ /-/ { print $2; }'
}

dump_grouped_sessions() {
	local current_session_group=""
	local original_session
	tmux list-sessions -F "$(grouped_sessions_format)" |
		grep "^1" |
		cut -c 3- |
		sort |
		while IFS=$d read session_group session_id session_name; do
			if [ "$session_group" != "$current_session_group" ]; then
				# this session is the original/first session in the group
				original_session="$session_name"
				current_session_group="$session_group"
			else
				# this session "points" to the original session
				active_window_index="$(get_active_window_index "$session_name")"
				alternate_window_index="$(get_alternate_window_index "$session_name")"
				echo "grouped_session${d}${session_name}${d}${original_session}${d}:${alternate_window_index}${d}:${active_window_index}"
			fi
		done
}

fetch_and_dump_grouped_sessions(){
	local grouped_sessions_dump="$(dump_grouped_sessions)"
	get_grouped_sessions "$grouped_sessions_dump"
	if [ -n "$grouped_sessions_dump" ]; then
		echo "$grouped_sessions_dump"
	fi
}

# translates pane pid to process command running inside a pane
dump_panes() {
	local full_command
	dump_panes_raw |
		while IFS=$d read line_type session_name window_number window_active window_flags pane_index pane_title dir pane_active pane_command pane_pid history_size; do
			# not saving panes from grouped sessions
			if is_session_grouped "$session_name"; then
				continue
			fi
			full_command="$(pane_full_command $pane_pid)"
			dir=$(echo $dir | sed 's/ /\\ /') # escape all spaces in directory path
			echo "${line_type}${d}${session_name}${d}${window_number}${d}${window_active}${d}${window_flags}${d}${pane_index}${d}${pane_title}${d}${dir}${d}${pane_active}${d}${pane_command}${d}:${full_command}"
		done
}

dump_windows() {
	dump_windows_raw |
		while IFS=$d read line_type session_name window_index window_name window_active window_flags window_layout; do
			# not saving windows from grouped sessions
			if is_session_grouped "$session_name"; then
				continue
			fi
			automatic_rename="$(tmux show-window-options -vt "${session_name}:${window_index}" automatic-rename)"
			# If the option was unset, use ":" as a placeholder.
			[ -z "${automatic_rename}" ] && automatic_rename=":"
			echo "${line_type}${d}${session_name}${d}${window_index}${d}${window_name}${d}${window_active}${d}${window_flags}${d}${window_layout}${d}${automatic_rename}"
		done
}

dump_state() {
	tmux display-message -p "$(state_format)"
}

dump_pane_contents() {
	local pane_contents_area="$(get_tmux_option "$pane_contents_area_option" "$default_pane_contents_area")"
	dump_panes_raw |
		while IFS=$d read line_type session_name window_number window_active window_flags pane_index pane_title dir pane_active pane_command pane_pid history_size; do
			capture_pane_contents "${session_name}:${window_number}.${pane_index}" "$history_size" "$pane_contents_area"
		done
}

# A save file is valid if it exists, is non-empty, and contains at least one
# `window<TAB>` line — the minimal structural element resurrect needs to
# restore. A partial/failed dump (tmux server hiccup, signal mid-write, OOM)
# typically produces an empty file or one with only session lines.
save_file_is_valid() {
	local path="$1"
	[ -s "$path" ] && grep -q $'^window\t' "$path"
}

remove_old_backups() {
	# remove resurrect files older than 30 days (default), but keep at least 5 copies of backup.
	local delete_after="$(get_tmux_option "$delete_backup_after_option" "$default_delete_backup_after")"
	local -a files
	files=($(ls -t $(resurrect_dir)/${RESURRECT_FILE_PREFIX}_*.${RESURRECT_FILE_EXTENSION} | tail -n +6))
	[[ ${#files[@]} -eq 0 ]] && return

	# Never delete the file currently pointed at by `last`, even if it falls
	# outside the 5 most-recent-by-mtime window. Otherwise a long-quiet system
	# whose `last` is older than 30 days would lose its only restorable save
	# and `last` would dangle.
	local last_link="$(resurrect_dir)/last"
	local last_target=""
	if [ -L "$last_link" ]; then
		last_target="$(resurrect_dir)/$(readlink "$last_link")"
	fi

	local -a deletable=()
	local f
	for f in "${files[@]}"; do
		[[ "$f" == "$last_target" ]] && continue
		deletable+=("$f")
	done
	[[ ${#deletable[@]} -eq 0 ]] && return
	for f in "${deletable[@]}"; do
		if find "$f" -type f -mtime "+${delete_after}" -print | grep -q .; then
			rm -f "$f"
			local companion="$(companion_file_path "$f")"
			[ -n "$companion" ] && rm -f "$companion"
		fi
	done
}

log_save_phase() {
	echo "tmux-resurrect: phase=$1 status=$2${3:+ $3}" >&2
}

remove_staged_pair() {
	local layout_tmp="$1" layout_final="$2" companion="$3"
	rm -f "$layout_tmp" "$layout_final"
	[ -n "$companion" ] && rm -f "$companion"
}

update_last_symlink() {
	local layout="$1" last_link="$2"
	local staged_link="${last_link}.tmp.$$"
	rm -f "$staged_link"
	ln -s "$(basename "$layout")" "$staged_link" || return 1
	mv -f "$staged_link" "$last_link"
}

save_all() {
	local resurrect_file_path="$(resurrect_file_path)"
	local last_resurrect_file="$(last_resurrect_file)"
	local tmp_path="${resurrect_file_path}.tmp"
	local companion_path="$(companion_file_path "$resurrect_file_path")"
	mkdir -p "$(resurrect_dir)"

	# Refuse a same-second filename collision instead of overwriting a pair that
	# may still be selected by `last`.
	if [ -n "$companion_path" ] && { [ -e "$resurrect_file_path" ] || [ -e "$companion_path" ]; }; then
		log_save_phase "layout-dump" "failed" "reason=filename-collision"
		return 1
	fi

	log_save_phase "layout-dump" "started" "path=$tmp_path"
	if ! {
		fetch_and_dump_grouped_sessions > "$tmp_path" &&
		dump_panes   >> "$tmp_path" &&
		dump_windows >> "$tmp_path" &&
		dump_state   >> "$tmp_path"
	}; then
		log_save_phase "layout-dump" "failed" "previous-save=preserved"
		remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
		return 1
	fi
	log_save_phase "layout-dump" "complete"

	log_save_phase "companion" "started"
	if ! execute_hook "post-save-layout" "$tmp_path"; then
		log_save_phase "companion" "failed" "previous-save=preserved"
		remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
		return 1
	fi
	if [ -n "$companion_path" ] && [ ! -s "$companion_path" ]; then
		log_save_phase "companion" "failed" "reason=missing-or-empty path=$companion_path"
		remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
		return 1
	fi
	log_save_phase "companion" "complete" "${companion_path:+path=$companion_path}"

	if ! save_file_is_valid "$tmp_path"; then
		log_save_phase "validation" "failed" "path=$tmp_path previous-save=preserved"
		remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
		return 1
	fi
	log_save_phase "validation" "complete"

	log_save_phase "promotion" "started"
	if ! mv -f "$tmp_path" "$resurrect_file_path"; then
		log_save_phase "promotion" "failed" "previous-save=preserved"
		remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
		return 1
	fi

	if capture_pane_contents_option_on; then
		log_save_phase "pane-archive" "started"
		mkdir -p "$(pane_contents_dir "save")"
		if ! dump_pane_contents || ! pane_contents_create_archive; then
			log_save_phase "pane-archive" "failed" "previous-save=preserved"
			remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
			return 1
		fi
		rm -f "$(pane_contents_dir "save")"/*
		log_save_phase "pane-archive" "complete"
	fi

	# The atomic rename of this symlink is the commit point. A restorer sees
	# either the previous pair or the fully validated new pair.
	if [ -n "$companion_path" ]; then
		if ! update_last_symlink "$resurrect_file_path" "$last_resurrect_file"; then
			log_save_phase "promotion" "failed" "reason=last-symlink previous-save=preserved"
			remove_staged_pair "$tmp_path" "$resurrect_file_path" "$companion_path"
			return 1
		fi
	elif files_differ "$resurrect_file_path" "$last_resurrect_file"; then
		if ! update_last_symlink "$resurrect_file_path" "$last_resurrect_file"; then
			log_save_phase "promotion" "failed" "reason=last-symlink previous-save=preserved"
			rm -f "$resurrect_file_path"
			return 1
		fi
	else
		rm -f "$resurrect_file_path"
	fi
	log_save_phase "promotion" "complete" "last=$(readlink "$last_resurrect_file")"

	remove_old_backups
	if ! execute_hook "post-save-all"; then
		log_save_phase "finalize" "failed"
		return 1
	fi
	log_save_phase "finalize" "complete"
}

show_output() {
	[ "$SCRIPT_OUTPUT" != "quiet" ]
}

main() {
	if supported_tmux_version_ok; then
		if show_output; then
			start_spinner "Saving..." "Tmux environment saved!"
		fi
		local save_status=0
		save_all || save_status=$?
		if show_output; then
			stop_spinner
			if [ "$save_status" -eq 0 ]; then
				display_message "Tmux environment saved!"
			else
				display_message "Tmux environment save failed; previous save preserved"
			fi
		fi
		return "$save_status"
	fi
	return 1
}
main
