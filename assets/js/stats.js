/* kerbal.ru — живые цифры GitHub на страницах сайта.
 *
 * Отдельного блока «статистика» нет намеренно: числа подставляются в уже
 * существующие элементы разметки —
 *   [data-release-link], footer .gh   ← звёзды репозитория
 *   [data-build-downloads]            ← скачивания пакета сборки
 *                                       (сборку задаёт [data-build-id] на
 *                                        самом элементе или на его родителе)
 *   [data-release-download]           ← общее число скачиваний релизов
 *   [data-contributors]               ← аватарки участников
 *
 * Источник — снимок /data/stats.json от tools/gen_stats.py: он работает без
 * сети и уже содержит соавторов, которых API contributors не отдаёт (Claude
 * приходит трейлером Co-Authored-By). Поверх снимка идёт живой запрос к
 * api.github.com; анонимный лимит — 60 запросов в час на IP, не попали —
 * молча остаётся снимок.
 */
(function () {
  'use strict';

  var REPO = 'plagness/kerbal.ru';
  var STAR = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.6l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5-5.8-3-5.8 3 1.1-6.5L2.6 9.4l6.5-.9z"/></svg>';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function num(n) {
    return String(n == null ? 0 : n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }
  function plural(n, one, few, many) {
    var a = Math.abs(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b > 1 && b < 5) return few;
    if (b === 1) return one;
    return many;
  }

  function paintStars(stars) {
    if (stars == null) return;
    document.querySelectorAll('[data-release-link], footer .gh').forEach(function (node) {
      var old = node.querySelector('.gh-stat');
      if (old) old.remove();
      node.insertAdjacentHTML('beforeend',
        '<span class="gh-stat" title="' + num(stars) + ' ' +
        plural(stars, 'звезда', 'звезды', 'звёзд') + ' на GitHub">' + STAR + num(stars) + '</span>');
    });
  }

  function paintDownloads(repo) {
    var byBuild = repo.downloadsByBuild || {};
    document.querySelectorAll('[data-build-downloads]').forEach(function (slot) {
      var host = slot.closest('[data-build-id]') || slot;
      var id = host.getAttribute('data-build-id');
      var n = byBuild[id];
      if (n == null) return;            // ноль показываем, отсутствие данных — нет
      slot.title = num(n) + ' ' + plural(n, 'скачивание', 'скачивания', 'скачиваний') +
        ' пакета сборки';
      slot.innerHTML = '<svg class="ic"><use href="#i-download"/></svg>' + num(n);
    });
    if (!repo.downloads) return;
    document.querySelectorAll('[data-release-download]').forEach(function (link) {
      var old = link.querySelector('.gh-hint');
      if (old) old.remove();
      link.insertAdjacentHTML('beforeend',
        '<span class="gh-hint" title="скачиваний за все релизы">· ' + num(repo.downloads) + '</span>');
    });
  }

  function paintPeople(people) {
    var target = document.querySelector('[data-contributors]');
    if (!target || !people || !people.length) return;
    target.innerHTML = people.map(function (p) {
      if (!p.avatar) return '';
      var label = esc(p.name) + ' — ' + esc((p.roles || []).join(', ')) +
        ' · ' + num(p.commits) + ' ' + plural(p.commits, 'коммит', 'коммита', 'коммитов');
      var img = '<img src="' + esc(p.avatar) + '" alt="" loading="lazy">';
      if (!p.url) return '<span class="team-avatar" title="' + label + '">' + img + '</span>';
      return '<a class="team-avatar" href="' + esc(p.url) + '" aria-label="' + label +
        '" title="' + label + '">' + img + '</a>';
    }).join('');
  }

  function apply(stats) {
    window.__kerbalStats = stats;
    var repo = stats.repo || {};
    paintStars(repo.stars);
    paintDownloads(repo);
    paintPeople(stats.people);
  }

  function live(stats) {
    fetch('https://api.github.com/repos/' + REPO, { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (info) {
        stats.repo = stats.repo || {};
        stats.repo.stars = info.stargazers_count;
        stats.repo.forks = info.forks_count;
        return fetch('https://api.github.com/repos/' + REPO + '/releases?per_page=100',
          { cache: 'no-cache' });
      })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (list) {
        var total = 0, byBuild = {};
        list.forEach(function (rel) {
          (rel.assets || []).forEach(function (a) {
            total += a.download_count;
            // <сборка>.ckan  и  kerbalru-translations-<сборка>-<версия>.zip
            var m = a.name.match(/^([a-z0-9]+)\.ckan$/) ||
                    a.name.match(/^kerbalru-translations-([a-z0-9]+)-/);
            if (m) byBuild[m[1]] = (byBuild[m[1]] || 0) + a.download_count;
          });
        });
        stats.repo.releases = list.length;
        stats.repo.downloads = total;
        stats.repo.downloadsByBuild = byBuild;
        apply(stats);
      })
      .catch(function () { /* остаётся снимок из stats.json */ });
  }

  fetch('/data/stats.json', { cache: 'no-cache' })
    .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then(function (stats) { apply(stats); live(stats); })
    .catch(function (e) { console.warn('stats:', e.message); });
})();
