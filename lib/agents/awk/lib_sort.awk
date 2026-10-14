# lib/agents/awk/lib_sort.awk — ordering, shared by report.awk and sample.awk.

# sortk ARR KEYS N — KEYS[1..N], busiest (largest ARR[key]) first.
# Busiest first; ties by name, so every awk (BSD, gawk, mawk, BusyBox) agrees.
function sortk(arr, keys, cnt,   i, j, b, t) {
    for (i = 1; i <= cnt; i++) {
        b = i
        for (j = i + 1; j <= cnt; j++) if (arr[keys[j]] > arr[keys[b]] || (arr[keys[j]] == arr[keys[b]] && keys[j] < keys[b])) b = j
        t = keys[i]; keys[i] = keys[b]; keys[b] = t
    }
}
