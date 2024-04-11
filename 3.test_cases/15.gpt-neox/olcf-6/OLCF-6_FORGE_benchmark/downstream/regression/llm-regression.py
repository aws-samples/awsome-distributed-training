from sklearn.linear_model import LinearRegression, BayesianRidge, Ridge, SGDRegressor
from sklearn.metrics import r2_score
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split, cross_val_score, KFold
import os, argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

def reg(data_X, data_y, title='regression'):

    reg_lin = BayesianRidge()
    scores = cross_val_score(reg_lin, data_X, data_y, 
                             cv=KFold(5, shuffle=True), scoring='neg_mean_squared_error') 
    X_train, X_test, y_train, y_test = train_test_split(data_X, data_y, random_state = 0,
                                                        test_size = 0.1)     
    reg_lin.fit(X_train, y_train)
    y_pred = reg_lin.predict(X_test)
    plt.plot(y_test, y_pred, 'bo')
    plt.plot(y_test, y_test, "k", linestyle='dotted')
    plt.xlabel(r"$E_{test}$ (Ry)")
    plt.ylabel(r"$E_{pred}$ (Ry)")
    plt.title(title)
    plt.ticklabel_format(axis='both', style='sci', scilimits=(0,3))
    plt.grid(color='silver', linestyle='dotted')
    plt.savefig('%s.png'%title, dpi=300, bbox_inches='tight')  
    return scores.mean()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Regression task command line arguments',\
            formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--data', default=None, help='input simulation data in csv')
    parser.add_argument('--emb', default=None, help='input embedding in csv')
    args = parser.parse_args()
 
    sim_df = pd.read_csv(args.data, header=0)
    model_df = pd.read_csv(args.emb, header=0)

    df = pd.merge(model_df, sim_df, on='conc') 
    print(df)
    df.to_csv('all.csv', index=False)
 
    sim_X = sim_df.values[:, :-1]
    sim_y = sim_df.values[:, -1]
    X = df.values[:, :-1]
    y = df.values[:, -1]
   

    sim_mse = reg(sim_X, sim_y, 'Simulation data')
    all_mse = reg(X, y, 'Simulation data + LLM embedding')

    print('MSE on simulation data: ', -sim_mse)
    print('MSE on simulation data + LLM embedding: ', -all_mse)
    print('Improvement: %.0f%% '%(100*(sim_mse-all_mse)/sim_mse))
         
