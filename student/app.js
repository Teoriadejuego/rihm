(() => {
  "use strict";

  const behaviourLabels = {
    altruist: "Altruist",
    egalitarian: "Egalitarian",
    selfish: "Selfish",
    antisocial: "Antisocial",
    inconsistent: "Inconsistent"
  };
  const socialBehaviours = ["altruist", "egalitarian", "selfish", "antisocial"];
  const state = { data: null, selectedBehaviours: new Set(Object.keys(behaviourLabels)) };
  const byId = (id) => document.getElementById(id);

  function setStatus(message, error = false) {
    const node = byId("dataStatus");
    node.textContent = message;
    node.classList.toggle("error", error);
  }

  function availableCountries() {
    const values = state.data.cells
      .filter((cell) => cell.scope === "international")
      .map((cell) => cell.country);
    return [...new Set(values)].sort((a, b) => {
      if (a === "All Countries") return -1;
      if (b === "All Countries") return 1;
      return a.localeCompare(b);
    });
  }

  function setupControls() {
    const country = byId("countrySelect");
    country.innerHTML = "";
    const countries = availableCountries();
    countries.forEach((name) => {
      const option = document.createElement("option");
      option.value = name;
      option.textContent = name;
      country.appendChild(option);
    });
    if (countries.includes("Spain")) country.value = "Spain";

    const controls = byId("behaviourControls");
    controls.innerHTML = "";
    Object.entries(behaviourLabels).forEach(([value, label]) => {
      const wrapper = document.createElement("label");
      const input = document.createElement("input");
      input.type = "checkbox";
      input.value = value;
      input.checked = true;
      input.addEventListener("change", () => {
        if (input.checked) state.selectedBehaviours.add(value);
        else state.selectedBehaviours.delete(value);
        render();
      });
      wrapper.append(input, document.createTextNode(label));
      controls.appendChild(wrapper);
    });
    [country, byId("genderSelect"), byId("matrixScope")].forEach((control) => {
      control.addEventListener("change", render);
    });
  }

  function findCell(scope, country, gender, behaviour) {
    return state.data.cells.find((cell) =>
      cell.scope === scope && cell.country === country &&
      cell.gender === gender && cell.behaviour === behaviour
    );
  }

  function displayNumber(value) {
    return value === null || value === undefined ? "Hidden" : Number(value).toLocaleString();
  }

  function displayPercent(cell) {
    return !cell || cell.suppressed || cell.percentage === null ? "Hidden" : `${Number(cell.percentage).toFixed(1)}%`;
  }

  function renderBars(containerId, scope, country, gender) {
    const container = byId(containerId);
    container.innerHTML = "";
    const selected = Object.keys(behaviourLabels).filter((name) => state.selectedBehaviours.has(name));
    if (!selected.length) {
      container.innerHTML = '<div class="empty-state">Select at least one behaviour.</div>';
      return;
    }
    selected.forEach((behaviour) => {
      const cell = findCell(scope, country, gender, behaviour);
      const row = document.createElement("div");
      const suppressed = !cell || cell.suppressed || cell.percentage === null;
      row.className = `md-bar-row${suppressed ? " suppressed" : ""}`;
      const width = suppressed ? 0 : Math.max(0, Math.min(100, Number(cell.percentage)));
      row.innerHTML = `
        <span class="md-bar-label">${behaviourLabels[behaviour]}</span>
        <span class="md-bar-track"><span class="md-bar-fill" style="display:block;width:${width}%"></span></span>
        <span class="md-bar-value">${suppressed ? "Hidden" : `${Number(cell.percentage).toFixed(1)}%`}</span>`;
      row.setAttribute("aria-label", `${behaviourLabels[behaviour]}: ${suppressed ? "hidden for privacy" : `${Number(cell.percentage).toFixed(1)} percent`}`);
      container.appendChild(row);
    });
  }

  function sampleNumbers(scope, country, gender) {
    const rows = state.data.cells.filter((cell) =>
      cell.scope === scope && cell.country === country && cell.gender === gender && !cell.suppressed
    );
    const row = rows.find((cell) => cell.n_complete !== null) || null;
    return row ? { complete: row.n_complete, consistent: row.n_consistent } : { complete: null, consistent: null };
  }

  function renderMetrics(country, gender) {
    const classSample = sampleNumbers("class", "Class", gender);
    const referenceSample = sampleNumbers("international", country, gender);
    byId("classComplete").textContent = displayNumber(classSample.complete);
    byId("classConsistent").textContent = displayNumber(classSample.consistent);
    byId("referenceComplete").textContent = displayNumber(referenceSample.complete);
    byId("referenceConsistent").textContent = displayNumber(referenceSample.consistent);
  }

  function renderTable(country, gender) {
    const body = byId("comparisonTable");
    body.innerHTML = "";
    Object.keys(behaviourLabels)
      .filter((name) => state.selectedBehaviours.has(name))
      .forEach((behaviour) => {
        const classCell = findCell("class", "Class", gender, behaviour);
        const referenceCell = findCell("international", country, gender, behaviour);
        const denominator = behaviour === "inconsistent" ? "Complete" : "Consistent";
        const row = document.createElement("tr");
        row.innerHTML = `
          <td>${behaviourLabels[behaviour]}</td>
          <td>${classCell && !classCell.suppressed ? displayNumber(classCell.count) : "Hidden"}</td>
          <td>${displayPercent(classCell)}</td>
          <td>${referenceCell && !referenceCell.suppressed ? displayNumber(referenceCell.count) : "Hidden"}</td>
          <td>${displayPercent(referenceCell)}</td>
          <td>${denominator}</td>`;
        body.appendChild(row);
      });
  }

  function renderInsight(country, gender) {
    const comparisons = socialBehaviours
      .filter((behaviour) => state.selectedBehaviours.has(behaviour))
      .map((behaviour) => ({
        behaviour,
        classCell: findCell("class", "Class", gender, behaviour),
        referenceCell: findCell("international", country, gender, behaviour)
      }))
      .filter(({ classCell, referenceCell }) =>
        classCell && referenceCell && !classCell.suppressed && !referenceCell.suppressed &&
        classCell.percentage !== null && referenceCell.percentage !== null
      )
      .map((item) => ({
        ...item,
        gap: Number(item.classCell.percentage) - Number(item.referenceCell.percentage)
      }))
      .sort((a, b) => Math.abs(b.gap) - Math.abs(a.gap));

    const paragraph = byId("guidedInsight").querySelector("p");
    if (!comparisons.length) {
      paragraph.textContent = "No comparable social indicator is visible with these filters. Try another reference, gender or indicator.";
      return;
    }

    const largest = comparisons[0];
    const genderLabel = gender === "all" ? "all respondents" : gender;
    if (Math.abs(largest.gap) < 0.05) {
      paragraph.textContent = `The visible social indicators have the same percentages in the class and ${country} (${genderLabel}). Try another filter, then ask whether sample size or suppression changes what you can conclude.`;
      return;
    }
    const direction = largest.gap >= 0 ? "higher" : "lower";
    paragraph.textContent = `Largest visible difference: ${behaviourLabels[largest.behaviour]} is ${Math.abs(largest.gap).toFixed(1)} percentage points ${direction} in the class than in ${country} (${genderLabel}). This shows where the samples differ—not why.`;
  }

  function renderMatrix(country, gender) {
    const scope = byId("matrixScope").value;
    const matrixCountry = scope === "class" ? "Class" : country;
    const cells = state.data.matrix_cells.filter((cell) =>
      cell.scope === scope && cell.country === matrixCountry && cell.gender === gender
    );
    const grid = byId("matrixGrid");
    grid.innerHTML = "";
    for (let compassion = 4; compassion >= 1; compassion -= 1) {
      for (let envy = 1; envy <= 4; envy += 1) {
        const cell = cells.find((item) =>
          Number(item.compassion_level) === compassion && Number(item.envy_level) === envy
        );
        const suppressed = !cell || cell.suppressed || cell.percentage === null;
        const node = document.createElement("div");
        node.className = `matrix-cell${suppressed ? " suppressed" : ""}`;
        if (suppressed) {
          node.textContent = "Hidden";
          node.title = `Compassion ${compassion}, envy ${envy}: privacy suppressed`;
        } else {
          const intensity = Math.min(.82, .08 + Number(cell.percentage) / 120);
          node.style.backgroundColor = `rgba(27, 110, 194, ${intensity})`;
          node.style.color = intensity > .48 ? "white" : "#0b3d91";
          node.textContent = `${Number(cell.percentage).toFixed(1)}%`;
          node.title = `Compassion ${compassion}, envy ${envy}: ${cell.count} of ${cell.denominator_n}`;
        }
        node.setAttribute("aria-label", node.title);
        grid.appendChild(node);
      }
    }
  }

  function render() {
    if (!state.data || !state.data.cells.length) return;
    const country = byId("countrySelect").value;
    const gender = byId("genderSelect").value;
    byId("referenceTitle").textContent = country;
    renderMetrics(country, gender);
    renderInsight(country, gender);
    renderBars("classBars", "class", "Class", gender);
    renderBars("referenceBars", "international", country, gender);
    renderTable(country, gender);
    renderMatrix(country, gender);
  }

  async function initialise() {
    try {
      const response = await fetch("data/public_results.json", { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      state.data = await response.json();
      const metadata = state.data.metadata || {};
      const updated = metadata.generated_at_utc
        ? new Date(metadata.generated_at_utc).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" })
        : "Not yet published";
      byId("publicationMeta").innerHTML = `
        <strong>Classroom results</strong><br>${updated}${metadata.generated_at_utc ? " UTC" : ""}
        ${metadata.generated_at_utc ? `<br><span>${metadata.publication_id || "Unknown"}</span>` : ""}`;
      if (!Array.isArray(state.data.cells) || !state.data.cells.length) {
        setStatus("The dashboard is ready. Classroom results will appear here after the teacher publishes a snapshot.");
        document.querySelectorAll(".control-panel, .guided-insight, .sample-grid, .comparison-grid, .table-card, .matrix-card").forEach((node) => {
          node.style.display = "none";
        });
        return;
      }
      setupControls();
      setStatus("Static snapshot loaded. Filters and charts now run entirely in this browser.");
      render();
    } catch (error) {
      setStatus(`The published snapshot could not be loaded: ${error.message}`, true);
    }
  }

  initialise();
})();
