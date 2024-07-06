class LiveMap {

    constructor(_config, _data) {
      this.config = {
        parentElement: _config.parentElement,
        containerWidth: _config.containerWidth || 700,
        containerHeight: _config.containerHeight || 700,
        margin: { top: 20, bottom: 20, right: 20, left: 20 }
      }
  
      this.data = _data; 
      // Call a class function
      this.initVis();
    }
  
    initVis() {
      let vis = this;
      console.log("init",this.data)
      vis.width = vis.config.containerWidth - vis.config.margin.left - vis.config.margin.right;
      vis.height = vis.config.containerHeight - vis.config.margin.top - vis.config.margin.bottom;
  
      // Atttempting to get things working just from using the scaled domain and range
      // We may need to get an offset value to apply across X and y if this doesnt work.

      console.log("Setting up scales")
      vis.xScale = d3.scaleLinear()
          .domain(d3.extent(this.data, d=> d.midX))
          .range([0, vis.width]);
  
      vis.yScale = d3.scaleLinear()
          .domain(d3.extent(this.data, d => d.midY))
          .range([vis.height, 0]) // May need to inverse?
       
  
      // Define size of SVG drawing area
      vis.svg = d3.select(vis.config.parentElement)
          .attr('width', vis.config.containerWidth)
          .attr('height', vis.config.containerHeight);
  
      // Append group element that will contain our actual chart (see margin convention)
      vis.chart = vis.svg.append('g')
          .attr('transform', `translate(${vis.config.margin.left},${vis.config.margin.top})`);

      
      vis.xValue = d => d.midX;
      vis.yValue = d => d.midY;
      vis.width = d => d.width;
    
  
      vis.line = d3.line() // Should be a good line, how do we set width??
          .x(d => vis.xScale(vis.xValue(d)))
          .y(d => vis.yScale(vis.yValue(d)));
  
      // Set the scale input domains
      vis.xScale.domain(d3.extent(vis.data, vis.xValue));
      vis.yScale.domain(d3.extent(vis.data, vis.yValue));   
  
      vis.updateVis(); //leave this empty for now...
      //vis.renderVis();
    }
  
  
    //We will add live Cars and live data 
   updateVis() { 
      let vis = this;
      
  
      vis.renderVis();
   }
  
  
    /**
     * This function contains the D3 code for binding data to visual elements
     * Important: the chart is not interactive yet and renderVis() is intended
     * to be called only once; otherwise new paths would be added on top
     */
    renderVis() {
      let vis = this;

      // Outer path outline
      vis.chart.append('path')
        //.data([vis.data])
        .attr('class', 'chart-line')
        .attr('d',vis.line(vis.data))
        .attr("fill", "none")
        .attr("stroke", "black")
        .attr("stroke-width",25)

      // inner path outline
      vis.chart.append('path')
        //.data([vis.data])
        .attr('class', 'chart-line')
        .attr('d',vis.line(vis.data))
        .attr("fill", "none")
        .attr("stroke", "white")
        .attr("stroke-width",20)
      
     
        // Live Car locations
        // Can use code from Survival units evovlved...


    }
  
  }