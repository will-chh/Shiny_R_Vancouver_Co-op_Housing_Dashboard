# DSCI-532_2026_19_van-housing

## Vancouver Non-Market Housing Dashboard

LOOKING FOR AFFORDABLE HOUSING? TIRED OF TRUMP AFFECTING OUR CANADIAN ECONOMY?? 

DONT WORRY, YOU ARE IN THE RIGHT PLACE!!!!!!

This dashboard visualizes non-market housing projects in **Vancouver** using publicly available data. It is designed to help:

- **Residents & Renters**: Understand building options, types, and occupancy years of non-market housing.  
- **City Planners & Policymakers**: Track housing development and analyze trends over time.  

Users can filter projects by **clientele**, **bedrooms**, **accessibility**, and **occupancy year**. The dashboard displays:  

- **Total Units**: Aggregated housing units based on selected filters  
- **Buildings Table**: List of projects matching filter criteria  
- **Map Placeholder**: Intended for future geospatial visualization 

## Demo

Here is our Demo Video! 
▶ https://youtu.be/646B0TKdOjM

## Getting Started

### Installation

1. Clone this repository:
```bash
git clone https://github.com/UBC-MDS/UBC-MDS-DSCI-532_2026_19_van-housing.git
cd UBC-MDS-DSCI-532_2026_19_van-housing
```

2. Create and activate the conda environment:
```bash
conda env create -f environment.yml
conda activate 532-gp19
```

3. Install required packages from requirements.txt:
```bash
pip install -r requirements.txt
```

### Running the Dashboard Locally

```bash
shiny run src/app.py
```

The dashboard will be available at `http://localhost:8000`

### View the Dashboard Live

The dashboard can be viewed online from the following links:
- [Dev branch dashboard](https://019ca12b-70bc-0d29-8861-3aa67b7b1905.share.connect.posit.cloud/)  
- [Main branch dashboard](https://019ca11c-80e1-200e-f440-05e01724ec0a.share.connect.posit.cloud/)

## Contributing

Interested in contributing? Check out the [CONTRIBUTING.md](CONTRIBUTING.md) file for guidelines on how to contribute to this project.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Code of Conduct

Please note that this project is released with a [Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

## Team Members
- William Chong
- Claudia Liauw
- Jimmy Wang
- Sidharth Malik
