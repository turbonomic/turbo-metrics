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

// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// PrometheusServerSpec defines the desired state of PrometheusServer
type PrometheusServerSpec struct {
	// Address of the Prometheus server.
	Address string `json:"address"`

	// Clusters is an optional list of ClusterConfiguration structs that specify information about the clusters
	// that the Prometheus server should obtain metrics for.
	// If this field is not specified, the Prometheus server obtains metrics only for the cluster where the
	// Prometurbo probe is running.
	// +optional
	Clusters []ClusterConfiguration `json:"clusters,omitempty"`
}

type PrometheusServerStatusType string

const (
	PrometheusServerStatusOK    PrometheusServerStatusType = "ok"
	PrometheusServerStatusError PrometheusServerStatusType = "error"
)

type PrometheusServerStatusReason string

const (
	PrometheusServerConnectionFailure     PrometheusServerStatusReason = "ConnectionFailure"
	PrometheusServerAuthenticationFailure PrometheusServerStatusReason = "AuthenticationFailure"
)

// PrometheusServerStatus defines the observed state of PrometheusServer
type PrometheusServerStatus struct {
	// +optional
	State PrometheusServerStatusType `json:"state,omitempty"`

	// +optional
	Reason PrometheusServerStatusReason `json:"reason,omitempty"`

	// +optional
	Message string `json:"message,omitempty"`

	// +optional
	Clusters []ClusterStatus `json:"clusters,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// PrometheusServer is the Schema for the prometheusservers API
type PrometheusServer struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PrometheusServerSpec   `json:"spec,omitempty"`
	Status PrometheusServerStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// PrometheusServerList contains a list of PrometheusServer
type PrometheusServerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []PrometheusServer `json:"items"`
}

func init() {
	SchemeBuilder.Register(&PrometheusServer{}, &PrometheusServerList{})
}
