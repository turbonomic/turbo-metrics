/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type ClusterConfiguration struct {
	// The labels that identify the cluster when executing PromQL query against the Prometheus server
	// +optional
	ClusterLabels map[string]string `json:"clusterLabels,omitempty"`

	// The unique ID of the cluster
	// Get the ID by running the following command in the cluster:
	//     kubectl -n default get svc kubernetes -ojsonpath='{.metadata.uid}'
	// If not specified, defaults to the ID of the cluster where the Prometurbo probe is running
	// +optional
	ID string `json:"id,omitempty"`

	// The Label selector for PrometheusExporters
	// If not defined, defaults to all PrometheusExporter resources in the current namespace
	// +optional
	ExporterSelector *metav1.LabelSelector `json:"exporterSelector,omitempty"`
}

type ClusterStatus struct {
	ID                string         `json:"id"`
	Entities          []EntityStatus `json:"entities,omitempty"`
	LastDiscoveryTime *metav1.Time   `json:"lastDiscoveryTime,omitempty"`
}
