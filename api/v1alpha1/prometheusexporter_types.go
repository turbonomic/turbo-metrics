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

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// PrometheusExporterSpec defines the desired state of PrometheusExporter
type PrometheusExporterSpec struct {
	// EntityConfigs specifies how entities can be constructed from metrics
	// exposed by this type of prometheus exporter
	// +kubebuilder:validation:MinItems:=1
	EntityConfigs []EntityConfiguration `json:"entities"`
}

type PrometheusExporterStatusType string

const (
	PrometheusExporterStatusOK    PrometheusExporterStatusType = "ok"
	PrometheusExporterStatusError PrometheusExporterStatusType = "error"
)

type PrometheusExporterStatusReason string

const (
	PrometheusExporterInvalidPromQLSyntax        PrometheusExporterStatusReason = "InvalidPromQLSyntax"
	PrometheusExporterInvalidMetricDefinition    PrometheusExporterStatusReason = "InvalidMetricDefinition"
	PrometheusExporterInvalidAttributeDefinition PrometheusExporterStatusReason = "InvalidAttributeDefinition"
)

// PrometheusExporterStatus defines the observed state of PrometheusExporter
type PrometheusExporterStatus struct {
	// +optional
	State PrometheusExporterStatusType `json:"state,omitempty"`
	// +optional
	Reason PrometheusExporterStatusReason `json:"reason,omitempty"`
	// +optional
	Message string `json:"message,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// PrometheusExporter is the Schema for the prometheusexporters API
type PrometheusExporter struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PrometheusExporterSpec   `json:"spec,omitempty"`
	Status PrometheusExporterStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// PrometheusExporterList contains a list of PrometheusExporter
type PrometheusExporterList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []PrometheusExporter `json:"items"`
}

func init() {
	SchemeBuilder.Register(&PrometheusExporter{}, &PrometheusExporterList{})
}
