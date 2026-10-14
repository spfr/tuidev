# lib/agents/awk/lib_sort.awk — ordering, shared by report.awk and sample.awk.
# Heapsorts: no recursion, and n log n on any input (a month of runs).

# sortk ARR KEYS N — KEYS[1..N] (distinct), busiest (largest ARR[key]) first;
# ties by name, so every awk (BSD, gawk, mawk, BusyBox) agrees.
function sortk(arr, keys, cnt,   i, t) {
    for (i = int(cnt / 2); i >= 1; i--) _sortk_sift(arr, keys, i, cnt)
    for (i = cnt; i > 1; i--) { t = keys[1]; keys[1] = keys[i]; keys[i] = t; _sortk_sift(arr, keys, 1, i - 1) }
}
# _sortk_first ARR X Y — true when key X goes before key Y.
function _sortk_first(arr, x, y) { return arr[x] > arr[y] || (arr[x] == arr[y] && x < y) }
# A heap with the key that goes last at its root.
function _sortk_sift(arr, keys, i, n,   c, t) {
    while ((c = 2 * i) <= n) {
        if (c < n && _sortk_first(arr, keys[c], keys[c + 1])) c++
        if (!_sortk_first(arr, keys[i], keys[c])) return
        t = keys[i]; keys[i] = keys[c]; keys[c] = t; i = c
    }
}

# sortn ARR N — ARR[1..N], numbers, smallest first.
function sortn(a, n,   i, t) {
    for (i = int(n / 2); i >= 1; i--) _sortn_sift(a, i, n)
    for (i = n; i > 1; i--) { t = a[1]; a[1] = a[i]; a[i] = t; _sortn_sift(a, 1, i - 1) }
}
function _sortn_sift(a, i, n,   c, t) {
    while ((c = 2 * i) <= n) {
        if (c < n && a[c + 1] + 0 > a[c] + 0) c++
        if (a[i] + 0 >= a[c] + 0) return
        t = a[i]; a[i] = a[c]; a[c] = t; i = c
    }
}
