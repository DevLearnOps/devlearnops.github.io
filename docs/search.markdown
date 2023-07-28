---
layout: default
permalink: /search
description: Search the DevLearnOps archive
---

<div id="search-container">
  <div>
    <span>Search the archive:</span>
    <input type="text" id="search-input" placeholder="Search..." autofocus>
  </div>
  <h2>Search results:</h2>
  <ul id="results-container"></ul>
</div>

<script src="/assets/js/simple-search.js" type="text/javascript"></script>

<script>
SimpleJekyllSearch({
  searchInput: document.getElementById('search-input'),
  resultsContainer: document.getElementById('results-container'),
  json: '/search.json'
})
</script>
